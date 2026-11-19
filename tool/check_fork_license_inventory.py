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
    return subprocess.check_output(["git", "-c", "core.quotepath=false", *args], cwd=ROOT, text=True).strip()


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
    deleted: set[str] = set()
    for line in raw.splitlines():
        fields = line.split("\t")
        code = fields[0]
        if code.startswith(("R", "C")):
            deleted.add(fields[1])
            path, status = fields[2], "added"
        elif code == "A":
            path, status = fields[1], "added"
        elif code == "M" or code.startswith("T"):
            path, status = fields[1], "modified"
        elif code == "D":
            deleted.add(fields[1])
            continue
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
    listed_deleted = set(data["deleted_paths"])
    deleted_missing = sorted(deleted - listed_deleted)
    deleted_stale = sorted(listed_deleted - deleted)
    if missing or stale or status_changed or deleted_missing or deleted_stale:
        fail(f"inventory mismatch; missing={missing[:20]}, stale={stale[:20]}, status_changed={status_changed[:20]}, deleted_missing={deleted_missing[:20]}, deleted_stale={deleted_stale[:20]}")

    dep5_text = DEP5.read_text(encoding="utf-8")
    dep5_map: dict[str, str] = {}
    for paragraph in dep5_text.split("\n\n"):
        lines = paragraph.splitlines()
        if not lines or not lines[0].startswith("Files:"):
            continue
        paths = []
        in_files = True
        for line in lines[1:]:
            if in_files and line.startswith(" "):
                paths.extend(line.split())
            else:
                in_files = False
        license_lines = [line for line in lines if line.startswith("License:")]
        if len(license_lines) != 1:
            fail("each DEP5 paragraph must have exactly one License field")
        expression = license_lines[0].split(":", 1)[1].strip()
        for path in paths:
            if path in dep5_map:
                fail(f"duplicate DEP5 mapping: {path}")
            dep5_map[path] = expression

    expected_dep5 = set(by_path)
    if set(dep5_map) != expected_dep5:
        fail(f"DEP5 path set mismatch; missing={sorted(expected_dep5-set(dep5_map))[:20]}, extra={sorted(set(dep5_map)-expected_dep5)[:20]}")
    for path, entry in by_path.items():
        cls, lic, status = entry["classification"], entry["license"], entry["status"]
        if dep5_map[path] != lic:
            fail(f"DEP5 expression mismatch for {path}: inventory={lic}, DEP5={dep5_map[path]}")
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

    print(f"LICENSE CHECK: PASS — {len(entries)} changed paths inventoried; {len(deleted)} deletions verified; DEP5 exact path/expression coverage complete; exclusions preserved; license copies identical.")


if __name__ == "__main__":
    main()
