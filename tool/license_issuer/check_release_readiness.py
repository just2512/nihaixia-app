#!/usr/bin/env python3
"""Block Release readiness unless a production-only issuer trust anchor is configured."""
from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_NAME = "YANJI_LICENSE_KEY_RING"
FIXTURE = ROOT / "test/fixtures/pro-license-test-vectors.json"
PRODUCTION_ROOTS = (ROOT / "lib", ROOT / "android/app/src/main")
ALLOWED_STATUSES = {"active", "standby", "retired", "revoked", "compromised"}
TRUSTED_STATUSES = {"active", "standby"}


def fail(message: str) -> None:
    print(f"RELEASE TRUST GATE: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def decode_public_key(value: object, label: str) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", value):
        fail(f"{label}: public key must be canonical Base64URL")
    try:
        decoded = base64.urlsafe_b64decode(value + "=")
    except (ValueError, binascii.Error):
        fail(f"{label}: invalid Base64URL")
    if len(decoded) != 32 or base64.urlsafe_b64encode(decoded).decode().rstrip("=") != value:
        fail(f"{label}: public key must encode exactly 32 canonical bytes")
    return decoded


def production_files(extra_scan_paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for root in PRODUCTION_ROOTS:
        if not root.exists():
            fail(f"required production source root is missing: {root.relative_to(ROOT)}")
        files.extend(path for path in root.rglob("*") if path.is_file())
    for candidate in extra_scan_paths:
        path = candidate if candidate.is_absolute() else ROOT / candidate
        if not path.is_file():
            fail(f"required scan artifact is missing: {path}")
        files.append(path)
    return files


def scan_payloads(path: Path):
    """Scan raw file bytes and each uncompressed ZIP entry (e.g. APK contents)."""
    try:
        display_path = str(path.relative_to(ROOT))
    except ValueError:
        display_path = str(path)

    try:
        raw = path.read_bytes()
        yield display_path, raw
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                for entry in archive.infolist():
                    if entry.is_dir():
                        continue
                    yield f"{display_path}!/{entry.filename}", archive.read(entry)
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        fail(f"cannot scan {display_path}: {error}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--scan-path",
        action="append",
        type=Path,
        default=[],
        help="additional built artifact to scan, such as a Release APK",
    )
    args = parser.parse_args()
    source = os.environ.get(ENV_NAME, "")
    if not source.strip():
        fail(f"{ENV_NAME} is not configured; production Release publication is blocked")

    try:
        config = json.loads(source)
    except json.JSONDecodeError as error:
        fail(f"{ENV_NAME} is not valid JSON: {error}")

    if not isinstance(config, dict) or set(config) != {"keys"}:
        fail("Key Ring root must contain only the keys property")

    keys = config["keys"]
    if not isinstance(keys, list) or not keys:
        fail("production Key Ring must contain at least one issuer key")

    ids: set[str] = set()
    has_trust_anchor = False
    public_key_bytes: dict[str, bytes] = {}
    for index, entry in enumerate(keys):
        label = f"keys[{index}]"
        if not isinstance(entry, dict) or set(entry) != {
            "key_id", "public_key_base64url", "status"
        }:
            fail(f"{label}: expected key_id, public_key_base64url and status only")
        key_id = entry["key_id"]
        status = entry["status"]
        if not isinstance(key_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", key_id):
            fail(f"{label}: issuer key_id has an invalid format")
        if key_id == "test-issuer-01" or key_id.startswith("test-"):
            fail(f"{label}: test issuer IDs are forbidden")
        if key_id in ids:
            fail(f"{label}: duplicate issuer ID {key_id}")
        ids.add(key_id)
        if not isinstance(status, str) or status not in ALLOWED_STATUSES:
            fail(f"{label}: unknown status {status!r}")
        if status in TRUSTED_STATUSES:
            has_trust_anchor = True
        public_key_bytes[key_id] = decode_public_key(
            entry["public_key_base64url"], label
        )

    if not has_trust_anchor:
        fail("revoked/compromised keys cannot be the only Release trust anchors")

    try:
        fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        if fixture.get("issuer_key_id") != "test-issuer-01":
            fail("test fixture issuer ID changed; update the release boundary test")
        test_public_key = decode_public_key(
            fixture.get("issuer_public_key_raw_base64url"), "test fixture"
        )
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read test issuer vector: {error}")

    if "test-issuer-01" in ids:
        fail("test issuer ID is forbidden in Release Key Ring")
    if test_public_key in public_key_bytes.values():
        fail("test fixture public key must never be a Release trust anchor")

    encoded_forms = {
        base64.urlsafe_b64encode(test_public_key).decode().rstrip("="),
        base64.b64encode(test_public_key).decode(),
        test_public_key.hex(),
    }
    for path in production_files(args.scan_path):
        for display_path, content in scan_payloads(path):
            lowered = content.lower()
            if test_public_key in content:
                fail(f"raw test issuer public key found in {display_path}")
            if b"test-issuer-01" in lowered:
                fail(f"test issuer ID found in {display_path}")
            for encoded in encoded_forms:
                candidates = (encoded.encode(), encoded.lower().encode())
                if any(candidate in content or candidate in lowered for candidate in candidates):
                    fail(f"encoded test issuer public key found in {display_path}")

    print(
        "RELEASE TRUST GATE: PASS — "
        f"{len(keys)} production issuer keys; "
        f"{sum(status in TRUSTED_STATUSES for status in (item['status'] for item in keys))} "
        "active/standby trust anchors; test issuer ID and public key excluded."
    )


if __name__ == "__main__":
    main()
