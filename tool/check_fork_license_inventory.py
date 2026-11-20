#!/usr/bin/env python3
"""Verify the Fork divergence inventory, SPDX mapping, and license boundaries."""
from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "c0f14e77a7fb721fc332576d21fef5f100392d0b"
RUNTIME_HEAD_MARKER = "HEAD (validated at CI runtime)"
INVENTORY = ROOT / "docs/fork-license-file-inventory.json"
DEP5 = ROOT / ".reuse/dep5"
LICENSE = ROOT / "LICENSE-FORK-COMMERCIAL.md"
LICENSE_COPY = ROOT / "LICENSES/LicenseRef-Nihaixia-Fork-Commercial.md"
ROOT_LICENSE = ROOT / "LICENSE"
APACHE_COPY = ROOT / "LICENSES/Apache-2.0.txt"

COMMERCIAL = "LicenseRef-Nihaixia-Fork-Commercial"
DUAL = "Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial"
EXCLUDED = "NOASSERTION"
OWNED_CLASSES = {"FORK_COMMERCIAL", "APACHE_2_0_AND_FORK_COMMERCIAL"}
EXCLUDED_CLASSES = {"KNOWLEDGE_BASE_EXCLUDED", "THIRD_PARTY_EXCLUDED"}
ALLOWED_CLASSES = OWNED_CLASSES | EXCLUDED_CLASSES
METADATA_PATHS = {
    ".reuse/dep5",
    "LICENSE-FORK-COMMERCIAL.md",
    "LICENSE-AI-COMMERCIAL.md",
}
METADATA_PREFIXES = ("LICENSES/",)


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=ROOT,
        text=True,
    ).strip()


def fail(message: str) -> None:
    print(f"LICENSE CHECK: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def is_metadata(path: str) -> bool:
    return path in METADATA_PATHS or path.startswith(METADATA_PREFIXES)


def changed_paths() -> tuple[dict[str, str], set[str]]:
    raw = git("diff", "--name-status", "--find-renames", BASE, "HEAD")
    actual: dict[str, str] = {}
    deleted: set[str] = set()
    for line in raw.splitlines():
        fields = line.split("\t")
        if not fields:
            continue
        code = fields[0]
        if code.startswith(("R", "C")):
            if len(fields) != 3:
                fail(f"unexpected rename/copy record: {line}")
            old_path, new_path = fields[1], fields[2]
            if not is_metadata(old_path):
                deleted.add(old_path)
            path, status = new_path, "added"
        elif code == "A":
            path, status = fields[1], "added"
        elif code == "M" or code.startswith("T"):
            path, status = fields[1], "modified"
        elif code == "D":
            if not is_metadata(fields[1]):
                deleted.add(fields[1])
            continue
        else:
            fail(f"unhandled git diff status {code!r} for {line}")
        if not is_metadata(path):
            actual[path] = status
    return actual, deleted


def parse_dep5(text: str) -> dict[str, str]:
    mapped: dict[str, str] = {}
    for paragraph in text.strip().split("\n\n"):
        lines = paragraph.splitlines()
        if not lines or not lines[0].startswith("Files:"):
            continue
        paths: list[str] = []
        reading_files = True
        for line in lines[1:]:
            if reading_files and line.startswith(" "):
                paths.extend(line.split())
            else:
                reading_files = False
        licenses = [line.split(":", 1)[1].strip() for line in lines if line.startswith("License:")]
        if len(licenses) != 1:
            fail("each DEP5 Files paragraph must contain exactly one License field")
        for path in paths:
            if path in mapped:
                fail(f"duplicate DEP5 path mapping: {path}")
            mapped[path] = licenses[0]
    return mapped


def main() -> None:
    try:
        git("cat-file", "-e", f"{BASE}^{{commit}}")
    except subprocess.CalledProcessError:
        fail(f"baseline commit {BASE} is unavailable; full history is required")

    data = json.loads(INVENTORY.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        fail("unsupported or missing inventory schema_version")
    if data.get("comparison_base") != BASE:
        fail("inventory comparison_base differs from the checker baseline")
    if data.get("comparison_head") != RUNTIME_HEAD_MARKER:
        fail("inventory comparison_head must be the runtime HEAD marker")

    entries = data.get("files")
    if not isinstance(entries, list):
        fail("inventory files must be an array")
    by_path: dict[str, dict[str, str]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            fail("inventory entry must be an object")
        path = entry.get("path")
        if not isinstance(path, str) or not path or path.startswith("/"):
            fail(f"invalid inventory path: {path!r}")
        if is_metadata(path):
            fail(f"license metadata must not appear in the covered-file inventory: {path}")
        if path in by_path:
            fail(f"duplicate inventory path: {path}")
        by_path[path] = entry

    actual, deleted = changed_paths()
    missing = sorted(set(actual) - set(by_path))
    stale = sorted(set(by_path) - set(actual))
    status_changed = sorted(
        path for path in set(actual) & set(by_path)
        if actual[path] != by_path[path].get("status")
    )
    listed_deleted = set(data.get("deleted_paths", []))
    deleted_missing = sorted(deleted - listed_deleted)
    deleted_stale = sorted(listed_deleted - deleted)
    if missing or stale or status_changed or deleted_missing or deleted_stale:
        fail(
            "inventory mismatch; "
            f"missing={missing[:20]}, stale={stale[:20]}, "
            f"status_changed={status_changed[:20]}, "
            f"deleted_missing={deleted_missing[:20]}, deleted_stale={deleted_stale[:20]}"
        )

    expected_category_counts = Counter(
        entry.get("classification") for entry in entries
    )
    status_counts = Counter(entry.get("status") for entry in entries)
    counts = data.get("counts", {})
    expected_counts = {
        "changed": len(entries),
        "added": status_counts.get("added", 0),
        "modified": status_counts.get("modified", 0),
        "deleted": len(deleted),
        "by_classification": dict(sorted(expected_category_counts.items())),
    }
    for key, value in expected_counts.items():
        if counts.get(key) != value:
            fail(f"inventory counts.{key} mismatch: expected={value}, recorded={counts.get(key)}")
    if sorted(expected_category_counts) != sorted(ALLOWED_CLASSES):
        fail(f"classification set mismatch: {sorted(expected_category_counts)}")

    for path, entry in by_path.items():
        classification = entry.get("classification")
        license_expression = entry.get("license")
        status = entry.get("status")
        rights_status = entry.get("rights_status")
        if classification not in ALLOWED_CLASSES:
            fail(f"unknown classification for {path}: {classification}")
        if not isinstance(entry.get("reason"), str) or not entry["reason"].strip():
            fail(f"missing classification rationale: {path}")

        if classification == "FORK_COMMERCIAL":
            if status != "added" or license_expression != COMMERCIAL:
                fail(f"new Fork-owned file must use {COMMERCIAL}: {path}")
            if rights_status != "OWNERSHIP_EVIDENCE_REQUIRED":
                fail(f"Fork-owned file must preserve explicit ownership evidence status: {path}")
        elif classification == "APACHE_2_0_AND_FORK_COMMERCIAL":
            if status != "modified" or license_expression != DUAL:
                fail(f"modified upstream-derived file must use {DUAL}: {path}")
            if rights_status != "OWNERSHIP_EVIDENCE_REQUIRED":
                fail(f"mixed file must preserve explicit ownership evidence status: {path}")
        elif classification in EXCLUDED_CLASSES:
            if license_expression != EXCLUDED:
                fail(f"knowledge-base/third-party content must remain NOASSERTION: {path}")
            if rights_status != "SOURCE_LICENSE_REVIEW":
                fail(f"excluded content must retain its source-license review status: {path}")

    dep5 = parse_dep5(DEP5.read_text(encoding="utf-8"))
    if set(dep5) != set(by_path):
        fail(
            "DEP5 exact path-set mismatch; "
            f"missing={sorted(set(by_path) - set(dep5))[:20]}, "
            f"extra={sorted(set(dep5) - set(by_path))[:20]}"
        )
    for path, entry in by_path.items():
        if dep5[path] != entry["license"]:
            fail(
                f"DEP5 expression mismatch for {path}: "
                f"inventory={entry['license']}, DEP5={dep5[path]}"
            )

    if LICENSE.read_bytes() != LICENSE_COPY.read_bytes():
        fail("commercial license and SPDX LicenseRef copy differ")
    if ROOT_LICENSE.read_bytes() != APACHE_COPY.read_bytes():
        fail("LICENSES/Apache-2.0.txt must remain byte-identical to root LICENSE")
    license_text = LICENSE.read_text(encoding="utf-8")
    required_clauses = [
        "公开或向第三方再分发",
        "事先书面许可",
        "无论该再分发是否收费",
        "Apache 2.0",
        "知识库及资料内容",
        "其他作者的原创内容",
        "GitHub 服务条款 D.5",
        "Private",
    ]
    missing_clauses = [phrase for phrase in required_clauses if phrase not in license_text]
    if missing_clauses:
        fail(f"commercial license is missing required clauses: {missing_clauses}")
    license_diff = subprocess.run(
        ["git", "diff", "--quiet", BASE, "HEAD", "--", "LICENSE"],
        cwd=ROOT,
        check=False,
    )
    if license_diff.returncode != 0:
        fail("root LICENSE changed; upstream Apache 2.0 text must remain intact")

    print(
        "LICENSE CHECK: PASS — "
        f"{len(entries)} changed paths; {len(deleted)} deletions; "
        f"categories={dict(sorted(expected_category_counts.items()))}; "
        "DEP5 exact path/expression coverage; source exclusions; "
        "license copies and root Apache text verified."
    )


if __name__ == "__main__":
    main()
