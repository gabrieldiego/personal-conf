#!/usr/bin/env python3

import argparse
import os
import shlex
import sys
from pathlib import Path
from datetime import datetime


def q(s: str) -> str:
    return shlex.quote(str(s))


def fmt_ts(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def rel_union(root_a: Path, root_b: Path):
    paths = set()

    for root in (root_a, root_b):
        for dirpath, dirnames, filenames in os.walk(root):
            base = Path(dirpath)
            for name in dirnames + filenames:
                full = base / name
                rel = full.relative_to(root)
                paths.add(rel)

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
    args = parser.parse_args()

    root_a = Path(args.folder_a).resolve()
    root_b = Path(args.folder_b).resolve()

    if not root_a.is_dir():
        print(f"Error: not a directory: {root_a}", file=sys.stderr)
        sys.exit(1)
    if not root_b.is_dir():
        print(f"Error: not a directory: {root_b}", file=sys.stderr)
        sys.exit(1)

    issues = 0

    for rel in rel_union(root_a, root_b):
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
