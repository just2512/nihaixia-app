from __future__ import annotations

import base64
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("check_release_readiness.py")
SPEC = importlib.util.spec_from_file_location("check_release_readiness", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
scanner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scanner)


def encoded_key(raw: bytes = bytes(range(32))) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def key_entry(
    key_id: str = "issuer-2026-01",
    status: str = "active",
    public_key: str | None = None,
) -> dict[str, str]:
    return {
        "key_id": key_id,
        "public_key_base64url": public_key or encoded_key(),
        "status": status,
    }


def ring(keys: list[dict[str, str]]) -> str:
    return json.dumps({"keys": keys}, separators=(",", ":"))


class ReleaseReadinessTests(unittest.TestCase):
    def invoke(self, value: str | None, artifact: bytes | None = None):
        env = {} if value is None else {scanner.ENV_NAME: value}
        with tempfile.TemporaryDirectory(dir=scanner.ROOT) as directory:
            args = [str(SCRIPT)]
            if artifact is not None:
                path = Path(directory) / "release.apk"
                path.write_bytes(artifact)
                args.extend(["--scan-path", str(path)])
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", args):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    try:
                        scanner.main()
                        code = 0
                    except SystemExit as error:
                        code = int(error.code or 0)
            return code, stdout.getvalue(), stderr.getvalue()

    def test_accepts_current_dart_key_ring_schema_with_active_and_standby(self):
        other_key = encoded_key(bytes(range(32, 64)))
        code, stdout, stderr = self.invoke(
            ring([key_entry(), key_entry("issuer-2026-02", "standby", other_key)])
        )
        self.assertEqual(code, 0, stderr)
        self.assertIn("2 production issuer keys", stdout)
        self.assertIn("2 active/standby trust anchors", stdout)

    def test_missing_key_ring_blocks_release_readiness(self):
        code, _, stderr = self.invoke(None)
        self.assertEqual(code, 1)
        self.assertIn("YANJI_LICENSE_KEY_RING is not configured", stderr)

    def test_rejects_legacy_schema_and_unknown_root_fields(self):
        values = (
            json.dumps({"schema_version": 1, "keys": [key_entry()]}),
            json.dumps({"keys": [key_entry()], "private_key": "forbidden"}),
        )
        for value in values:
            with self.subTest(value=value):
                code, _, stderr = self.invoke(value)
                self.assertEqual(code, 1)
                self.assertIn("root must contain only the keys property", stderr)

    def test_rejects_unknown_key_fields_and_duplicate_ids(self):
        extra = {**key_entry(), "private_key": "forbidden"}
        duplicate = [key_entry(), key_entry()]
        for keys in ([extra], duplicate):
            with self.subTest(keys=keys):
                code, _, stderr = self.invoke(ring(keys))
                self.assertEqual(code, 1)
                self.assertIn("FAIL:", stderr)

    def test_rejects_test_issuer_id_and_test_vector_public_key(self):
        fixture = json.loads(scanner.FIXTURE.read_text(encoding="utf-8"))
        test_key = fixture["issuer_public_key_raw_base64url"]
        for entry in (
            key_entry("test-issuer-01"),
            key_entry("issuer-2026-99", public_key=test_key),
        ):
            with self.subTest(entry=entry):
                code, _, stderr = self.invoke(ring([entry]))
                self.assertEqual(code, 1)
                self.assertIn("FAIL:", stderr)

    def test_retired_or_revoked_only_ring_does_not_pass_release_gate(self):
        other_key = encoded_key(bytes(range(32, 64)))
        code, _, stderr = self.invoke(
            ring([
                key_entry("issuer-2026-01", "retired"),
                key_entry("issuer-2026-02", "revoked", other_key),
            ])
        )
        self.assertEqual(code, 1)
        self.assertIn("cannot be the only Release trust anchors", stderr)

    def test_rejects_malformed_ids_keys_and_statuses(self):
        entries = (
            key_entry("Issuer-UPPER"),
            key_entry("issuer-2026-01", public_key="not-base64url"),
            key_entry("issuer-2026-02", "enabled"),
        )
        for entry in entries:
            with self.subTest(entry=entry):
                code, _, stderr = self.invoke(ring([entry]))
                self.assertEqual(code, 1)
                self.assertIn("FAIL:", stderr)

    def test_scans_release_artifact_for_test_issuer_id(self):
        code, _, stderr = self.invoke(
            ring([key_entry()]), b"classes.dex:test-issuer-01"
        )
        self.assertEqual(code, 1)
        self.assertIn("test issuer ID found", stderr)

    def test_scans_release_artifact_for_raw_test_public_key(self):
        fixture = json.loads(scanner.FIXTURE.read_text(encoding="utf-8"))
        raw = base64.urlsafe_b64decode(
            fixture["issuer_public_key_raw_base64url"] + "="
        )
        code, _, stderr = self.invoke(ring([key_entry()]), b"classes.dex:" + raw)
        self.assertEqual(code, 1)
        self.assertIn("raw test issuer public key found", stderr)

    def test_scans_release_artifact_for_encoded_test_public_key(self):
        fixture = json.loads(scanner.FIXTURE.read_text(encoding="utf-8"))
        encoded = fixture["issuer_public_key_raw_base64url"].encode()
        code, _, stderr = self.invoke(ring([key_entry()]), b"classes.dex:" + encoded)
        self.assertEqual(code, 1)
        self.assertIn("encoded test issuer public key found", stderr)


if __name__ == "__main__":
    unittest.main()
