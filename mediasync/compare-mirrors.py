#!/usr/bin/env python3

import argparse
import itertools
import os
import shlex
import sys
from pathlib import Path, PurePosixPath
from datetime import datetime


def q(s: str) -> str:
    return shlex.quote(str(s))


def fmt_ts(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def walk_limited(root: Path, max_depth=None):
    for dirpath, dirnames, filenames in os.walk(root):
        base = Path(dirpath)
        rel_dir = base.relative_to(root)
        depth = len(rel_dir.parts)

        if max_depth is not None and depth >= max_depth:
            dirnames[:] = []

        yield base, dirnames, filenames


def load_gitignore_rules(path: Path, base_rel: Path):
    rules = []

    if not path.is_file():
        return rules

    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()

        if not line:
            continue

        if line.startswith("\\#") or line.startswith("\\!"):
            line = line[1:]
        elif line.startswith("#"):
            continue

        negated = line.startswith("!")
        if negated:
            line = line[1:]

        if not line:
            continue

        directory_only = line.endswith("/")
        if directory_only:
            line = line.rstrip("/")

        anchored = line.startswith("/")
        if anchored:
            line = line.lstrip("/")

        has_slash = "/" in line

        rules.append(
            {
                "base_rel": base_rel,
                "pattern": line,
                "negated": negated,
                "directory_only": directory_only,
                "anchored": anchored,
                "has_slash": has_slash,
            }
        )

    return rules


def match_gitignore_rule(rel: Path, is_dir: bool, rule) -> bool:
    base_rel = rule["base_rel"]

    try:
        rel_from_base = rel.relative_to(base_rel) if base_rel != Path(".") else rel
    except ValueError:
        return False

    rel_posix = rel_from_base.as_posix()
    rel_path = PurePosixPath(rel_posix)
    pattern = rule["pattern"]

    if rule["anchored"] or rule["has_slash"]:
        if rel_posix == pattern or rel_posix.startswith(pattern + "/"):
            return True
        return rel_path.match(pattern)

    if rule["directory_only"]:
        parts_to_check = rel_from_base.parts if is_dir else rel_from_base.parts[:-1]
        return any(PurePosixPath(part).match(pattern) for part in parts_to_check)

    return any(PurePosixPath(part).match(pattern) for part in rel_from_base.parts)


def is_ignored(rel: Path, is_dir: bool, rules) -> bool:
    ignored = False

    for rule in rules:
        if match_gitignore_rule(rel, is_dir, rule):
            ignored = not rule["negated"]

    return ignored


def visible_paths(root: Path, max_depth=None, use_gitignore=True):
    paths = set()
    rules_by_dir = {}

    for dirpath, dirnames, filenames in os.walk(root):
        base = Path(dirpath)
        rel_dir = base.relative_to(root)
        depth = len(rel_dir.parts)

        current_rules = []

        if use_gitignore:
            if rel_dir != Path("."):
                current_rules = list(rules_by_dir.get(rel_dir.parent, []))

            current_rules.extend(load_gitignore_rules(base / ".gitignore", rel_dir))
            rules_by_dir[rel_dir] = current_rules

        if max_depth is not None and depth >= max_depth:
            dirnames[:] = []

        kept_dirnames = []

        for name in dirnames:
            rel = rel_dir / name if rel_dir != Path(".") else Path(name)

            if use_gitignore and is_ignored(rel, True, current_rules):
                continue

            kept_dirnames.append(name)
            paths.add(rel)

        dirnames[:] = kept_dirnames

        for name in filenames:
            rel = rel_dir / name if rel_dir != Path(".") else Path(name)

            if use_gitignore and is_ignored(rel, False, current_rules):
                continue

            paths.add(rel)

    return paths


def rel_union(root_a: Path, root_b: Path, max_depth=None, use_gitignore=True):
    paths = visible_paths(root_a, max_depth=max_depth, use_gitignore=use_gitignore)
    paths |= visible_paths(root_b, max_depth=max_depth, use_gitignore=use_gitignore)
    return sorted(paths, key=lambda p: str(p))


def rsync_file_cmd(src_root: Path, dst_root: Path, rel: Path) -> str:
    src = src_root / rel
    dst = dst_root / rel
    dst_parent = dst.parent
    return f"mkdir -p {q(dst_parent)} && rsync -a --times {q(src)} {q(dst)}"


def describe_type(p: Path) -> str:
    if not p.exists():
        return "missing"
    if p.is_file():
        return "file"
    if p.is_dir():
        return "directory"
    if p.is_symlink():
        return "symlink"
    return "other"


def main():
    parser = argparse.ArgumentParser(
        description="Compare two folders that are supposed to mirror each other."
    )
    parser.add_argument("folder_a", help="First folder")
    parser.add_argument("folder_b", help="Second folder")
    parser.add_argument(
        "--mtime-tolerance",
        type=float,
        default=2.0,
        help="Allowed modification-time difference in seconds (default: 2.0)",
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=None,
        help=(
            "Maximum folder depth to search. "
            "0 means only the root folder contents, 1 means one level deeper, "
            "default is unlimited."
        ),
    )
    parser.add_argument(
        "--no-gitignore",
        action="store_true",
        help=(
            "Disable automatic reading of .gitignore files from each compared "
            "folder and its subdirectories."
        ),
    )
    args = parser.parse_args()

    root_a = Path(args.folder_a).resolve()
    root_b = Path(args.folder_b).resolve()

    if args.max_depth is not None and args.max_depth < 0:
        print("--max-depth must be >= 0", file=sys.stderr)
        sys.exit(1)

    if not root_a.is_dir():
        print(f"Error: not a directory: {root_a}", file=sys.stderr)
        sys.exit(1)
    if not root_b.is_dir():
        print(f"Error: not a directory: {root_b}", file=sys.stderr)
        sys.exit(1)

    issues = 0

    for rel in rel_union(
        root_a,
        root_b,
        max_depth=args.max_depth,
        use_gitignore=not args.no_gitignore,
    ):
        a = root_a / rel
        b = root_b / rel

        a_exists = a.exists()
        b_exists = b.exists()

        if not a_exists and not b_exists:
            continue

        if a_exists and not b_exists:
            issues += 1
            print(f"[WARN] Missing in B: {rel}")
            print(f"       Present in A as {describe_type(a)}")
            if a.is_file():
                print(f"       Suggest A -> B: {rsync_file_cmd(root_a, root_b, rel)}")
            print()
            continue

        if b_exists and not a_exists:
            issues += 1
            print(f"[WARN] Missing in A: {rel}")
            print(f"       Present in B as {describe_type(b)}")
            if b.is_file():
                print(f"       Suggest B -> A: {rsync_file_cmd(root_b, root_a, rel)}")
            print()
            continue

        a_type = describe_type(a)
        b_type = describe_type(b)

        if a_type != b_type:
            issues += 1
            print(f"[WARN] Type mismatch: {rel}")
            print(f"       A: {a_type}")
            print(f"       B: {b_type}")
            print()
            continue

        if a.is_dir():
            continue

        if not a.is_file():
            issues += 1
            print(f"[WARN] Unsupported non-regular item: {rel}")
            print(f"       A: {a_type}")
            print(f"       B: {b_type}")
            print()
            continue

        stat_a = a.stat()
        stat_b = b.stat()

        size_diff = stat_a.st_size != stat_b.st_size
        mtime_diff = abs(stat_a.st_mtime - stat_b.st_mtime) > args.mtime_tolerance

        if size_diff or mtime_diff:
            issues += 1
            print(f"[WARN] Difference found: {rel}")
            print(
                f"       A: size={stat_a.st_size} mtime={fmt_ts(stat_a.st_mtime)}"
            )
            print(
                f"       B: size={stat_b.st_size} mtime={fmt_ts(stat_b.st_mtime)}"
            )

            if size_diff:
                print("       Reason: file sizes differ")
            elif mtime_diff:
                print("       Reason: modification times differ")

            newer_side = "A" if stat_a.st_mtime > stat_b.st_mtime else "B"
            print(f"       Newer side by mtime: {newer_side}")

            print(f"       Suggest A -> B: {rsync_file_cmd(root_a, root_b, rel)}")
            print(f"       Suggest B -> A: {rsync_file_cmd(root_b, root_a, rel)}")
            print()

    if issues == 0:
        print("No differences found.")
    else:
        print(f"Done. {issues} issue(s) found.")


if __name__ == "__main__":
    main()
