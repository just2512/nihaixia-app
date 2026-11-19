#!/usr/bin/env python3
"""Verify the Fork-owned license inventory against the upstream divergence."""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "c0f14e77a7fb721fc332576d21fef5f100392d0b"
INVENTORY = ROOT / "docs/fork-license-file-inventory.json"
DEP5 = ROOT / ".reuse/dep5"
LICENSE = ROOT / "LICENSE-FORK-COMMERCIAL.md"
LICENSE_COPY = ROOT / "LICENSES/LicenseRef-Nihaixia-Fork-Commercial.md"
EXCLUDED_PREFIXES = ("LICENSES/",)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def fail(message: str) -> None:
    print(f"LICENSE CHECK: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def is_metadata(path: str) -> bool:
    return path in {".reuse/dep5", "LICENSE-FORK-COMMERCIAL.md", "LICENSE-AI-COMMERCIAL.md"} or path.startswith(EXCLUDED_PREFIXES)


def main() -> None:
    try:
        git("cat-file", "-e", f"{BASE}^{{commit}}")
    except subprocess.CalledProcessError:
        fail(f"baseline commit {BASE} is unavailable; fetch full history before checking")

    raw = git("diff", "--name-status", "--find-renames", BASE, "HEAD")
    actual: dict[str, str] = {}
    for line in raw.splitlines():
        fields = line.split("\t")
        if fields[0].startswith(("R", "C")):
            path, status = fields[2], "added"
        elif fields[0] == "A":
            path, status = fields[1], "added"
        elif fields[0] == "M" or fields[0].startswith("T"):
            path, status = fields[1], "modified"
        else:
            continue
        if not is_metadata(path):
            actual[path] = status

    data = json.loads(INVENTORY.read_text(encoding="utf-8"))
    entries = data["files"]
    by_path = {entry["path"]: entry for entry in entries}
    if len(by_path) != len(entries):
        fail("duplicate paths in inventory")
    missing = sorted(set(actual) - set(by_path))
    stale = sorted(set(by_path) - set(actual))
    status_changed = sorted(p for p in set(actual) & set(by_path) if actual[p] != by_path[p]["status"])
    if missing or stale or status_changed:
        fail(f"inventory mismatch; missing={missing[:20]}, stale={stale[:20]}, status_changed={status_changed[:20]}")

    dep5_text = DEP5.read_text(encoding="utf-8")
    dep5_paths: set[str] = set()
    in_files = False
    for line in dep5_text.splitlines():
        if line.startswith("Files:"):
            in_files = True
            dep5_paths.update(line[6:].split())
        elif line.startswith(" ") and in_files:
            dep5_paths.update(line.split())
        elif line.strip() and not line.startswith(" "):
            in_files = False
    for path, entry in by_path.items():
        if path not in dep5_paths:
            fail(f"changed path missing from .reuse/dep5: {path}")
        cls, lic, status = entry["classification"], entry["license"], entry["status"]
        if cls in ("KNOWLEDGE_BASE_EXCLUDED", "THIRD_PARTY_EXCLUDED") and lic != "NOASSERTION":
            fail(f"excluded path must use NOASSERTION: {path}")
        if status == "modified" and cls not in ("KNOWLEDGE_BASE_EXCLUDED", "THIRD_PARTY_EXCLUDED") and lic != "Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial":
            fail(f"modified upstream file must carry dual-layer expression: {path}")
        if status == "added" and cls not in ("KNOWLEDGE_BASE_EXCLUDED", "THIRD_PARTY_EXCLUDED") and lic != "LicenseRef-Nihaixia-Fork-Commercial":
            fail(f"new Fork file must carry commercial expression: {path}")

    if LICENSE.read_bytes() != LICENSE_COPY.read_bytes():
        fail("commercial license text and SPDX LicenseRef copy differ")
    text = LICENSE.read_text(encoding="utf-8")
    required = ["公开或向第三方再分发", "事先书面许可", "无论该再分发是否收费", "Apache 2.0", "知识库及资料内容", "其他作者的原创内容"]
    absent = [phrase for phrase in required if phrase not in text]
    if absent:
        fail(f"commercial license text missing required clauses: {absent}")
    try:
        git("diff", "--quiet", BASE, "HEAD", "--", "LICENSE")
    except subprocess.CalledProcessError:
        fail("root LICENSE changed; upstream Apache 2.0 text must remain intact")

    print(f"LICENSE CHECK: PASS — {len(entries)} changed paths inventoried; {len(data['deleted_paths'])} deleted paths recorded; DEP5 coverage complete; exclusions preserved; license copies identical.")


if __name__ == "__main__":
    main()
