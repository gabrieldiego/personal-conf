#!/usr/bin/env python3
import argparse
import fnmatch
import json
import os
import sys
from pathlib import Path
from typing import Any

import requests


OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434/api/generate")
MODEL = os.environ.get("OLLAMA_MODEL", "coder-server")

DEFAULT_INCLUDE_PATTERNS = [
    "*.py", "*.js", "*.ts", "*.tsx", "*.jsx", "*.java", "*.c", "*.cc", "*.cpp",
    "*.h", "*.hpp", "*.go", "*.rs", "*.php", "*.rb", "*.sh", "*.zsh", "*.yaml",
    "*.yml", "*.json", "*.toml", "*.ini", "*.cfg", "*.conf", "*.md", "*.txt",
    "*.html", "*.css", "*.sql",
]

DEFAULT_EXCLUDE_DIRS = {
    ".git", ".hg", ".svn", "__pycache__", "node_modules", "dist", "build",
    ".next", ".venv", "venv", "env", ".mypy_cache", ".pytest_cache", ".idea",
    ".vscode", "coverage", "target", "vendor"
}

DEFAULT_EXCLUDE_FILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "poetry.lock",
    "Cargo.lock", ".DS_Store"
}

SYSTEM_PROMPT = """You are a coding assistant that proposes minimal safe patches for an existing codebase.

Return ONLY valid JSON with this exact shape:
{
  "summary": "short explanation",
  "patches": [
    {
      "path": "relative/path/from/project/root",
      "search": "exact old text to find",
      "replace": "new text to replace it with"
    }
  ]
}

Rules:
- Output JSON only. No markdown fences.
- You may patch multiple files, but only files that were provided.
- Each "search" must be an exact substring from the provided file content.
- Keep patches as small as possible.
- Do not invent files unless explicitly asked. For now, do not create new files.
- Do not rename files.
- Do not use unified diff format.
- Prefer a few surgical patches over rewriting whole files.
"""

MAX_FILE_BYTES = 120_000
MAX_TOTAL_BYTES = 700_000


def should_include_file(path: Path, include_patterns: list[str]) -> bool:
    name = path.name
    if name in DEFAULT_EXCLUDE_FILES:
        return False
    return any(fnmatch.fnmatch(name, pat) for pat in include_patterns)


def is_probably_text_file(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            chunk = f.read(4096)
        return b"\x00" not in chunk
    except OSError:
        return False


def build_tree(root: Path, included_files: list[Path]) -> str:
    lines: list[str] = []
    rels = sorted(str(p.relative_to(root)) for p in included_files)
    for rel in rels:
        lines.append(rel)
    return "\n".join(lines)


def collect_files(root: Path, include_patterns: list[str]) -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in DEFAULT_EXCLUDE_DIRS]
        current_dir = Path(dirpath)
        for filename in filenames:
            path = current_dir / filename
            if not should_include_file(path, include_patterns):
                continue
            if not is_probably_text_file(path):
                continue
            try:
                if path.stat().st_size > MAX_FILE_BYTES:
                    continue
            except OSError:
                continue
            files.append(path)
    return sorted(files)


def read_files_with_budget(root: Path, files: list[Path]) -> list[tuple[str, str]]:
    selected: list[tuple[str, str]] = []
    total = 0
    for path in files:
        rel = str(path.relative_to(root))
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
        except OSError:
            continue

        block_size = len(rel) + len(text)
        if total + block_size > MAX_TOTAL_BYTES:
            break
        selected.append((rel, text))
        total += block_size
    return selected


def build_prompt(project_root: Path, instruction: str, file_blocks: list[tuple[str, str]]) -> str:
    tree = "\n".join(rel for rel, _ in file_blocks)

    sections = [
        f"Project root: {project_root}",
        "",
        "User request:",
        instruction,
        "",
        "Provided files:",
        tree,
        "",
        "File contents:",
        "",
    ]

    for rel, content in file_blocks:
        sections.append(f"----- BEGIN FILE {rel} -----")
        sections.append(content)
        sections.append(f"----- END FILE {rel} -----")
        sections.append("")

    sections.append("Return only JSON.")
    return "\n".join(sections)


def strip_code_fences(text: str) -> str:
    text = text.strip()

    if text.startswith("```"):
        lines = text.splitlines()

        # Remove first fence line, e.g. ``` or ```json
        if lines and lines[0].startswith("```"):
            lines = lines[1:]

        # Remove final fence line if present
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]

        text = "\n".join(lines).strip()

    return text


def extract_first_json_object(text: str) -> str:
    start = text.find("{")
    if start == -1:
        raise ValueError("No JSON object found in model response")

    depth = 0
    in_string = False
    escape = False

    for i in range(start, len(text)):
        ch = text[i]

        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]

    raise ValueError("Could not find complete JSON object in model response")


def call_model(prompt: str) -> dict[str, Any]:
    response = requests.post(
        OLLAMA_URL,
        json={
            "model": MODEL,
            "prompt": SYSTEM_PROMPT + "\n\n" + prompt,
            "stream": False,
        },
        timeout=900,
    )
    response.raise_for_status()

    payload = response.json()
    text = payload["response"].strip()

    # 1. Try raw
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # 2. Try after stripping markdown fences
    stripped = strip_code_fences(text)
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass

    # 3. Try extracting first JSON object
    extracted = extract_first_json_object(stripped)
    try:
        return json.loads(extracted)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Model did not return valid JSON.\n\n{text}") from exc

def apply_patch(root: Path, patch: dict[str, str], dry_run: bool) -> bool:
    rel_path = patch["path"]
    search = patch["search"]
    replace = patch["replace"]

    file_path = (root / rel_path).resolve()

    if not file_path.exists():
        print(f"[WARN] Patch target does not exist: {rel_path}")
        return False

    content = file_path.read_text(encoding="utf-8")

    if search not in content:
        print(f"[WARN] Search block not found in {rel_path}")
        return False

    new_content = content.replace(search, replace, 1)

    if dry_run:
        print(f"[DRY RUN] Would patch: {rel_path}")
    else:
        file_path.write_text(new_content, encoding="utf-8")
        print(f"[OK] Patched: {rel_path}")

    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ask Ollama for safe patches across the whole current codebase."
    )
    parser.add_argument(
        "instruction",
        help="Natural-language request, e.g. 'Add a /health endpoint and improve logging'",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually write changes to disk",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        help="Additional glob pattern to include, e.g. --include '*.mjs'",
    )
    parser.add_argument(
        "--max-files",
        type=int,
        default=40,
        help="Maximum number of files to send to the model",
    )
    args = parser.parse_args()

    root = Path.cwd()
    include_patterns = DEFAULT_INCLUDE_PATTERNS + args.include

    files = collect_files(root, include_patterns)
    if not files:
        print("No matching text files found in current directory.", file=sys.stderr)
        return 1

    files = files[:args.max_files]
    file_blocks = read_files_with_budget(root, files)

    if not file_blocks:
        print("No readable files were selected within size budget.", file=sys.stderr)
        return 1

    print(f"Selected {len(file_blocks)} file(s) from {root}")
    for rel, _ in file_blocks:
        print(f"  - {rel}")

    prompt = build_prompt(root, args.instruction, file_blocks)

    try:
        result = call_model(prompt)
    except Exception as exc:
        print(f"\nError calling model: {exc}", file=sys.stderr)
        return 1

    print("\nSummary:")
    print(result.get("summary", "(no summary)"))

    patches = result.get("patches")
    if not isinstance(patches, list):
        print("\nError: model response missing 'patches' list", file=sys.stderr)
        return 1

    if not patches:
        print("\nNo patches proposed.")
        return 0

    print("\nProposed patches:")
    for i, patch in enumerate(patches, start=1):
        print(f"{i}. {patch.get('path', '?')}")

    print()
    applied = 0
    for patch in patches:
        try:
            if apply_patch(root, patch, dry_run=not args.apply):
                applied += 1
        except Exception as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)

    if args.apply:
        print(f"\nApplied {applied} patch(es).")
    else:
        print("\nDry run only. Re-run with --apply to write changes.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
