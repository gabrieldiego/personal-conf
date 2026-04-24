#!/usr/bin/env python3

import argparse
import os
import shlex
import sys
import unicodedata
from pathlib import Path, PurePosixPath
from datetime import datetime


def q(s: str) -> str:
    return shlex.quote(str(s))


def fmt_ts(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def normalize_text(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def normalize_rel(rel: Path) -> str:
    return "/".join(normalize_text(part) for part in rel.parts)


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
                "pattern": normalize_text(line),
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

    rel_posix = normalize_text(rel_from_base.as_posix())
    rel_path = PurePosixPath(rel_posix)
    pattern = rule["pattern"]

    if rule["anchored"] or rule["has_slash"]:
        if rel_posix == pattern or rel_posix.startswith(pattern + "/"):
            return True
        return rel_path.match(pattern)

    if rule["directory_only"]:
        parts_to_check = rel_from_base.parts if is_dir else rel_from_base.parts[:-1]
        return any(PurePosixPath(normalize_text(part)).match(pattern) for part in parts_to_check)

    return any(PurePosixPath(normalize_text(part)).match(pattern) for part in rel_from_base.parts)


def is_ignored(rel: Path, is_dir: bool, rules) -> bool:
    ignored = False

    for rule in rules:
        if match_gitignore_rule(rel, is_dir, rule):
            ignored = not rule["negated"]

    return ignored


def visible_path_index(root: Path, max_depth=None, use_gitignore=True):
    """
    Returns:
      entries: dict[normalized_rel -> raw_rel_path]
      collisions: dict[normalized_rel -> list[raw_rel_path]]
    """
    entries = {}
    collisions = {}
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

            key = normalize_rel(rel)
            prev = entries.get(key)
            if prev is None:
                entries[key] = rel
            elif prev != rel:
                collisions.setdefault(key, [prev])
                if rel not in collisions[key]:
                    collisions[key].append(rel)

        dirnames[:] = kept_dirnames

        for name in filenames:
            rel = rel_dir / name if rel_dir != Path(".") else Path(name)

            if use_gitignore and is_ignored(rel, False, current_rules):
                continue

            key = normalize_rel(rel)
            prev = entries.get(key)
            if prev is None:
                entries[key] = rel
            elif prev != rel:
                collisions.setdefault(key, [prev])
                if rel not in collisions[key]:
                    collisions[key].append(rel)

    return entries, collisions


def rsync_file_cmd(src_root: Path, dst_root: Path, rel_src: Path, rel_dst: Path | None = None) -> str:
    src = src_root / rel_src
    rel_dst = rel_src if rel_dst is None else rel_dst
    dst = dst_root / rel_dst
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

    index_a, collisions_a = visible_path_index(
        root_a, max_depth=args.max_depth, use_gitignore=not args.no_gitignore
    )
    index_b, collisions_b = visible_path_index(
        root_b, max_depth=args.max_depth, use_gitignore=not args.no_gitignore
    )

    for side, collisions in (("A", collisions_a), ("B", collisions_b)):
        for key, rels in sorted(collisions.items()):
            issues += 1
            print(f"[WARN] Unicode-normalization collision inside {side}: {key}")
            for rel in rels:
                print(f"       {rel}")
            print("       Rename one of these entries; they normalize to the same name.")
            print()

    all_keys = sorted(set(index_a) | set(index_b))

    for key in all_keys:
        rel_a = index_a.get(key)
        rel_b = index_b.get(key)

        a = (root_a / rel_a) if rel_a is not None else None
        b = (root_b / rel_b) if rel_b is not None else None

        display_rel = rel_a if rel_a is not None else rel_b

        a_exists = a is not None and a.exists()
        b_exists = b is not None and b.exists()

        if rel_a is not None and rel_b is not None and rel_a != rel_b:
            print(f"[INFO] Same logical path, different Unicode spelling:")
            print(f"       A: {rel_a}")
            print(f"       B: {rel_b}")
            print()

        if not a_exists and not b_exists:
            continue

        if a_exists and not b_exists:
            issues += 1
            print(f"[WARN] Missing in B: {display_rel}")
            print(f"       Present in A as {describe_type(a)}")
            if a.is_file():
                print(f"       Suggest A -> B: {rsync_file_cmd(root_a, root_b, rel_a)}")
            print()
            continue

        if b_exists and not a_exists:
            issues += 1
            print(f"[WARN] Missing in A: {display_rel}")
            print(f"       Present in B as {describe_type(b)}")
            if b.is_file():
                print(f"       Suggest B -> A: {rsync_file_cmd(root_b, root_a, rel_b)}")
            print()
            continue

        a_type = describe_type(a)
        b_type = describe_type(b)

        if a_type != b_type:
            issues += 1
            print(f"[WARN] Type mismatch: {display_rel}")
            print(f"       A: {a_type}")
            print(f"       B: {b_type}")
            print()
            continue

        if a.is_dir():
            continue

        if not a.is_file():
            issues += 1
            print(f"[WARN] Unsupported non-regular item: {display_rel}")
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
            print(f"[WARN] Difference found: {display_rel}")
            print(f"       A: size={stat_a.st_size} mtime={fmt_ts(stat_a.st_mtime)}")
            print(f"       B: size={stat_b.st_size} mtime={fmt_ts(stat_b.st_mtime)}")

            if size_diff:
                print("       Reason: file sizes differ")
            elif mtime_diff:
                print("       Reason: modification times differ")

            newer_side = "A" if stat_a.st_mtime > stat_b.st_mtime else "B"
            print(f"       Newer side by mtime: {newer_side}")

            print(f"       Suggest A -> B: {rsync_file_cmd(root_a, root_b, rel_a, rel_b or rel_a)}")
            print(f"       Suggest B -> A: {rsync_file_cmd(root_b, root_a, rel_b, rel_a or rel_b)}")
            print()

    if issues == 0:
        print("No differences found.")
    else:
        print(f"Done. {issues} issue(s) found.")


if __name__ == "__main__":
    main()
