#!/usr/bin/env python3
"""Audit current user-facing product branding across tracked repository text.

Knowledge-source corpora under assets/ are intentionally excluded: historical
institution/teacher references there are source content, not the app brand.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Define retired labels from UTF-8 bytes so this scanner does not match itself.
OLD_BRAND = bytes.fromhex("e6b189e59490e4b8ade58cbb").decode("utf-8")
OLD_AI_LABEL = (
    bytes.fromhex("e6b189e59490").decode("utf-8")
    + r"\s+AI\s+"
    + bytes.fromhex("e58aa9e6898b").decode("utf-8")
)
PATTERN = re.compile(rf"{re.escape(OLD_BRAND)}|{OLD_AI_LABEL}")

TEXT_SUFFIXES = {
    ".dart", ".kt", ".java", ".xml", ".yaml", ".yml", ".json", ".html",
    ".htm", ".plist", ".svg", ".md", ".txt", ".properties", ".gradle",
    ".kts", ".sh", ".py", ".ps1", ".bat", ".toml", ".css", ".rc", ".cfg",
    ".ini",
}
TEXT_FILENAMES = {"README", "LICENSE", "Makefile", ".gitignore"}

def is_scannable(path: str) -> bool:
    if path.startswith("assets/"):
        # Only the in-app changelog is product metadata; the other assets are
        # original knowledge sources / lesson material, not brand surfaces.
        return path == "assets/data/changelog.json"
    suffix = Path(path).suffix.lower()
    return suffix in TEXT_SUFFIXES or Path(path).name in TEXT_FILENAMES

def historical_artifact_only(path: str, line: str) -> bool:
    # Preserve exact historical APK names and a source-document keyword used
    # by the herb parser; neither is a current app-facing product label.
    if path == "tools/parse_herbs.py" and OLD_BRAND + "诊疗" in line:
        return True
    artifact = re.search(re.escape(OLD_BRAND) + r"_v[0-9][^\s|)]*\.apk", line)
    if not artifact:
        return False
    return (
        path in {"CHANGELOG.md", "APP_DEVELOPMENT_DETAIL.md"}
        or path.startswith("release/研纪_历史版本_")
    )

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="fail on non-historical old-brand matches")
    args = parser.parse_args()

    listing = subprocess.run(
        ["git", "ls-files", "-z"], check=True, stdout=subprocess.PIPE
    ).stdout
    paths = [p.decode("utf-8", errors="surrogateescape") for p in listing.split(b"\0") if p]
    findings: list[tuple[str, int, str, bool]] = []

    for path in paths:
        if not is_scannable(path):
            continue
        try:
            content = Path(path).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(content.splitlines(), start=1):
            if PATTERN.search(line):
                findings.append((path, number, line.strip(), historical_artifact_only(path, line)))

    disallowed = [row for row in findings if not row[3]]
    if findings:
        print("Brand audit matches:")
        for path, number, line, historical in findings:
            status = (
                "HISTORICAL-SOURCE-ALLOWLIST" if path == "tools/parse_herbs.py"
                else "HISTORICAL-ARTIFACT-ALLOWLIST" if historical
                else "REJECT"
            )
            print(f"{status} {path}:{number}: {line}")
    else:
        print("Brand audit: no retired product-name references found.")

    if disallowed:
        print(f"\nREJECT: {len(disallowed)} non-historical old-brand reference(s). Current public name must be 研纪.")
        return 1 if args.strict else 0

    print("\nPASS: current product-facing text is consistent with 研纪.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
