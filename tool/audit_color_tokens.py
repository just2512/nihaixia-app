#!/usr/bin/env python3
"""Inventory legacy Dart color literals and reject newly introduced UI literals.

The first pass is intentionally non-destructive: --inventory reports the existing
baseline without failing on historical usages. --changed-only blocks new hardcoded
colors outside the two approved theme-token definition files and the documented
domain-color allowlist.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
ALLOWLIST_PATH = ROOT / "tool" / "color_token_audit_allowlist.json"
TOKEN_FILES = {
    "lib/theme/yanji_palette.dart",
    "lib/theme/app_colors.dart",
}

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Color(0x...)", re.compile(r"\bColor\s*\(\s*0x[0-9a-fA-F]{6,8}\s*\)")),
    ("Color.fromARGB", re.compile(r"\bColor\s*\.\s*fromARGB\s*\(")),
    ("Color.fromRGBO", re.compile(r"\bColor\s*\.\s*fromRGBO\s*\(")),
    ("Colors.*", re.compile(r"\bColors\s*(?:\.\s*[A-Za-z_]\w*|\s*\[)")),
    ("opacity API", re.compile(r"\.\s*(?:withOpacity|withValues)\s*\(")),
    ("local ThemeData", re.compile(r"\bThemeData\s*\(")),
)


def load_allowlist() -> dict[str, str]:
    if not ALLOWLIST_PATH.exists():
        return {}
    data = json.loads(ALLOWLIST_PATH.read_text(encoding="utf-8"))
    files = data.get("files", {})
    if not isinstance(files, dict):
        raise ValueError("allowlist 'files' must be a path-to-reason object")
    normalized: dict[str, str] = {}
    for path, reason in files.items():
        if not isinstance(path, str) or not isinstance(reason, str) or not reason.strip():
            raise ValueError("each allowlist entry needs a path and a non-empty reason")
        normalized[path.replace("\\", "/")] = reason.strip()
    return normalized


def scan_inventory() -> int:
    counts: Counter[str] = Counter()
    file_counts: Counter[str] = Counter()
    for path in sorted(LIB.rglob("*.dart")):
        rel = path.relative_to(ROOT).as_posix()
        content = path.read_text(encoding="utf-8", errors="replace")
        for line_number, line in enumerate(content.splitlines(), start=1):
            for label, pattern in PATTERNS:
                matches = list(pattern.finditer(line))
                if matches:
                    counts[label] += len(matches)
                    file_counts[rel] += len(matches)
    total = sum(counts.values())
    print(f"Color-token inventory: {total} matches across {len(file_counts)} Dart files.")
    for label, count in counts.most_common():
        print(f"  {label}: {count}")
    print("Largest files by match count:")
    for path, count in file_counts.most_common(20):
        print(f"  {count:4d}  {path}")
    return total


def changed_lines(base_ref: str) -> list[tuple[str, int, str]]:
    command = [
        "git", "diff", "--no-ext-diff", "--unified=0",
        f"{base_ref}...HEAD", "--", "lib",
    ]
    result = subprocess.run(
        command, cwd=ROOT, check=False, text=True, capture_output=True
    )
    if result.returncode:
        raise RuntimeError(
            f"git diff failed ({result.returncode}): {result.stderr.strip()}"
        )
    current_path = ""
    current_line = 0
    added: list[tuple[str, int, str]] = []
    for line in result.stdout.splitlines():
        if line.startswith("+++ b/"):
            current_path = line[6:]
        elif line.startswith("@@"):
            match = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if match:
                current_line = int(match.group(1))
        elif line.startswith("+") and not line.startswith("+++"):
            added.append((current_path, current_line, line[1:]))
            current_line += 1
        elif line.startswith(" "):
            current_line += 1
    return added


def check_changed(base_ref: str) -> int:
    allowlist = load_allowlist()
    violations: list[tuple[str, int, str, str]] = []
    ignored_files = TOKEN_FILES | set(allowlist)
    for path, line_number, line in changed_lines(base_ref):
        normalized = path.replace("\\", "/")
        if not normalized.endswith(".dart") or normalized in ignored_files:
            continue
        for label, pattern in PATTERNS:
            match = pattern.search(line)
            if match:
                violations.append((normalized, line_number, label, line.strip()))
                break
    if violations:
        print("New hardcoded color/theme usages are not allowed outside token files:")
        for path, line_number, label, line in violations:
            print(f"  {path}:{line_number}: {label}: {line}")
        print(
            "Move the value into lib/theme/yanji_palette.dart or "
            "lib/theme/app_colors.dart, or add a narrowly justified entry "
            "to tool/color_token_audit_allowlist.json."
        )
        return 1
    print(f"PASS: no new hardcoded color/theme usages outside token files (base: {base_ref}).")
    if allowlist:
        print(f"Controlled domain-color allowlist entries: {len(allowlist)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", action="store_true")
    parser.add_argument("--changed-only", action="store_true")
    parser.add_argument("--base-ref", default="HEAD^")
    args = parser.parse_args()
    if not args.inventory and not args.changed_only:
        parser.error("choose --inventory, --changed-only, or both")
    if args.inventory:
        scan_inventory()
    if args.changed_only:
        return check_changed(args.base_ref)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"color-token audit error: {exc}", file=sys.stderr)
        raise SystemExit(2)
