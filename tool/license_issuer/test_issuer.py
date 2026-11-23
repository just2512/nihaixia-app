from __future__ import annotations

import base64
import hashlib
import json
import sqlite3
import tempfile
import unittest
from unittest import mock
import uuid
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

import issuer


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VECTOR_PATH = REPOSITORY_ROOT / "test" / "fixtures" / "pro-license-test-vectors.json"


def load_vectors() -> dict:
    return json.loads(VECTOR_PATH.read_text(encoding="utf-8"))


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_device_request() -> tuple[str, str, str, str]:
    private_key = ec.generate_private_key(ec.SECP256R1())
    spki = private_key.public_key().public_bytes(
        Encoding.DER,
        PublicFormat.SubjectPublicKeyInfo,
    )
    fingerprint = b64url(hashlib.sha256(spki).digest())
    request_nonce = b64url(b"N" * 32)
    payload = {
        "schema_version": 1,
        "request_id": str(uuid.uuid4()),
        "request_nonce": request_nonce,
        "app_id": issuer.APP_ID,
        "product_id": issuer.PRODUCT_ID,
        "issued_at": "2026-11-23T09:00:00Z",
        "device_public_key_spki": b64url(spki),
        "device_key_sha256": fingerprint,
        "device_key_security_level": "SOFTWARE",
    }
    payload_segment = b64url(issuer._canonical_json(payload))
    message = ("YANJIR1." + payload_segment).encode("ascii")
    signature = private_key.sign(message, ec.ECDSA(hashes.SHA256()))
    token = "YANJIR1." + payload_segment + "." + b64url(signature)
    request_sha256 = b64url(hashlib.sha256(token.encode("ascii")).digest())
    return token, fingerprint, request_nonce, request_sha256


class IssuerProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / "orders.sqlite3"
        self.issuer_key = ed25519.Ed25519PrivateKey.generate()
        self.issuer_public_key = self.issuer_key.public_key()

    def issue(
        self,
        request: str,
        order_id: str = "YJ-TEST-0001",
        *,
        reissue: bool = False,
        reason: str | None = None,
        private_key: ed25519.Ed25519PrivateKey | None = None,
        public_key: ed25519.Ed25519PublicKey | None = None,
        key_status: str = "active",
    ) -> str:
        return issuer.issue_license(
            request_token=request,
            order_id=order_id,
            issuer_key_id="issuer-test-01",
            issuer_private_key=private_key or self.issuer_key,
            issuer_public_key=public_key or self.issuer_public_key,
            issuer_key_status=key_status,
            database_path=self.db,
            reissue=reissue,
            reissue_reason=reason,
        )

    def test_shared_cross_language_vector_verifies(self) -> None:
        vectors = load_vectors()
        request = issuer.verify_device_request(vectors["device_request"]["token"])
        self.assertEqual(request["app_id"], vectors["app_id"])
        self.assertEqual(request["product_id"], vectors["product_id"])
        self.assertEqual(request["request_id"], vectors["device_request"]["request_payload"]["request_id"])
        self.assertEqual(request["request_nonce"], vectors["device_request"]["request_payload"]["request_nonce"])
        self.assertEqual(request["request_sha256"], vectors["device_request"]["request_sha256"])
        self.assertEqual(request["device_key_sha256"], vectors["device_request"]["device_key_sha256"])

        prefix, payload_segment, signature_segment = vectors["valid_license"]["token"].split(".")
        self.assertEqual(prefix, "YANJI1")
        payload = json.loads(issuer._b64url_decode(payload_segment).decode("utf-8"))
        self.assertEqual(payload, vectors["valid_license"]["payload"])
        public_key = ed25519.Ed25519PublicKey.from_public_bytes(
            issuer._b64url_decode(vectors["issuer_public_key_raw_base64url"], max_bytes=32)
        )
        public_key.verify(
            issuer._b64url_decode(signature_segment, max_bytes=64),
            ("YANJI1." + payload_segment).encode("ascii"),
        )

    def test_shared_vector_request_tampering_and_signature_tampering_fail(self) -> None:
        token = load_vectors()["device_request"]["token"]
        prefix, payload_segment, signature = token.split(".")
        payload = json.loads(issuer._b64url_decode(payload_segment))
        payload["app_id"] = "com.example.other"
        changed_segment = b64url(issuer._canonical_json(payload))
        with self.assertRaises(issuer.IssuerError):
            issuer.verify_device_request(prefix + "." + changed_segment + "." + signature)

        signature_bytes = bytearray(issuer._b64url_decode(signature))
        signature_bytes[-1] ^= 0x01
        with self.assertRaises(issuer.IssuerError):
            issuer.verify_device_request(
                prefix + "." + payload_segment + "." + b64url(bytes(signature_bytes))
            )

    def test_valid_request_issues_v12_device_bound_canonical_token(self) -> None:
        vectors = load_vectors()
        request_token = vectors["device_request"]["token"]
        request = issuer.verify_device_request(request_token)
        token = self.issue(request_token)
        prefix, payload_segment, signature_segment = token.split(".")
        self.assertEqual(prefix, "YANJI1")
        payload_bytes = issuer._b64url_decode(payload_segment)
        payload = json.loads(payload_bytes)
        self.assertEqual(payload_bytes, issuer._canonical_json(payload))
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["product_id"], issuer.PRODUCT_ID)
        self.assertEqual(payload["protocol_revision"], issuer.PROTOCOL_REVISION)
        self.assertTrue(payload["perpetual"])
        self.assertEqual(
            payload["device_public_key_sha256"],
            vectors["device_request"]["device_key_sha256"],
        )
        self.assertEqual(payload["request_id"], request["request_id"])
        self.assertEqual(
            payload["features"],
            ["ai_advanced", "contextual_assistant"],
        )
        self.assertEqual(
            set(payload),
            {
                "schema_version",
                "license_id",
                "order_id",
                "product_id",
                "protocol_revision",
                "app_id",
                "perpetual",
                "features",
                "device_public_key_sha256",
                "request_id",
                "issued_at",
                "issuer_key_id",
            },
        )
        signature = issuer._b64url_decode(signature_segment)
        self.issuer_public_key.verify(
            signature,
            issuer.LICENSE_SIGNATURE_DOMAIN + issuer._canonical_json(payload),
        )
        self.assertNotIn("request_nonce", payload)
        self.assertNotIn("request_sha256", payload)
        self.assertNotIn("device_key_security_level", payload)
        with sqlite3.connect(self.db) as connection:
            issuer_record = connection.execute(
                """
                SELECT request_nonce, request_sha256, device_key_security_level
                FROM issued_licenses WHERE license_id = ?
                """,
                (payload["license_id"],),
            ).fetchone()
        self.assertEqual(
            issuer_record,
            (
                vectors["device_request"]["request_payload"]["request_nonce"],
                vectors["device_request"]["request_sha256"],
                vectors["device_request"]["request_payload"]["device_key_security_level"],
            ),
        )

    def test_issuer_refuses_reserved_feature_overissuance(self) -> None:
        request, _, _, _ = make_device_request()
        with mock.patch.dict(
            issuer.ISSUABLE_FEATURES_BY_REVISION,
            {issuer.PROTOCOL_REVISION: ("ai_advanced", "advanced_learning")},
        ):
            with self.assertRaises(issuer.IssuerError):
                self.issue(request)


    def test_same_order_and_same_request_is_idempotent(self) -> None:
        request, _, _, _ = make_device_request()
        self.assertEqual(self.issue(request), self.issue(request))

    def test_order_reissue_requires_explicit_operator_action(self) -> None:
        first_request, _, _, _ = make_device_request()
        second_request, _, _, _ = make_device_request()
        first_token = self.issue(first_request)
        with self.assertRaises(issuer.IssuerError):
            self.issue(second_request, reissue=False)
        with self.assertRaises(issuer.IssuerError):
            self.issue(second_request, reissue=True)
        second_token = self.issue(
            second_request,
            reissue=True,
            reason="Customer reinstalled after clearing application data",
        )
        self.assertNotEqual(first_token, second_token)

        with sqlite3.connect(self.db) as connection:
            rows = connection.execute(
                """
                SELECT license_id, status, reissue_sequence, replaced_by_license_id
                FROM issued_licenses WHERE order_id = ?
                ORDER BY reissue_sequence
                """,
                ("YJ-TEST-0001",),
            ).fetchall()
            events = connection.execute(
                "SELECT event_type FROM issuer_audit_events WHERE order_id = ? ORDER BY occurred_at",
                ("YJ-TEST-0001",),
            ).fetchall()
            order = connection.execute(
                "SELECT reissue_count FROM orders WHERE order_id = ?",
                ("YJ-TEST-0001",),
            ).fetchone()

        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0][1], "superseded")
        self.assertEqual(rows[0][2], 0)
        self.assertEqual(rows[0][3], rows[1][0])
        self.assertEqual(rows[1][1], "active")
        self.assertEqual(rows[1][2], 1)
        self.assertEqual(order[0], 1)
        self.assertEqual([row[0] for row in events], ["license_issued", "license_reissued"])

        listed = issuer.list_orders(self.db)
        self.assertEqual(len(listed), 2)
        self.assertTrue(all(row[3] == issuer.PRODUCT_ID for row in listed))
        self.assertEqual({row[2] for row in listed}, {"active", "superseded"})

    def test_request_id_cannot_be_attached_to_another_order(self) -> None:
        request, _, _, _ = make_device_request()
        self.issue(request, "YJ-TEST-0001")
        with self.assertRaises(issuer.IssuerError):
            self.issue(request, "YJ-TEST-0002")

    def test_wrong_private_key_or_wrong_issuer_key_id_pair_is_rejected(self) -> None:
        request, _, _, _ = make_device_request()
        wrong_private_key = ed25519.Ed25519PrivateKey.generate()
        with self.assertRaises(issuer.IssuerError):
            self.issue(
                request,
                private_key=wrong_private_key,
                public_key=self.issuer_public_key,
            )
        with self.assertRaises(issuer.IssuerError):
            self.issue(request, key_status="retired")

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with self.assertRaises(issuer.IssuerError):
            issuer._decode_json_object(b'{"schema_version":1,"schema_version":1}')

    def test_legacy_issuer_records_are_preserved_but_marked_unbound(self) -> None:
        with sqlite3.connect(self.db) as connection:
            connection.execute(
                """
                CREATE TABLE issued_orders (
                    order_id TEXT PRIMARY KEY,
                    request_id TEXT NOT NULL UNIQUE,
                    license_id TEXT NOT NULL UNIQUE,
                    product_id TEXT NOT NULL,
                    device_key_sha256 TEXT NOT NULL,
                    issuer_key_id TEXT NOT NULL,
                    issued_at TEXT NOT NULL,
                    license_token TEXT NOT NULL
                )
                """
            )
            connection.execute(
                """
                INSERT INTO issued_orders VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "YJ-LEGACY-0001",
                    "legacy-request",
                    "LIC-LEGACY-0001",
                    issuer.PRODUCT_ID,
                    "A" * 43,
                    "issuer-legacy",
                    "2026-11-22T00:00:00Z",
                    "legacy-token-do-not-activate",
                ),
            )
        issuer.initialize_database(self.db)
        with sqlite3.connect(self.db) as connection:
            row = connection.execute(
                """
                SELECT status, request_sha256, license_token
                FROM issued_licenses WHERE license_id = ?
                """,
                ("LIC-LEGACY-0001",),
            ).fetchone()
            version = connection.execute("PRAGMA user_version").fetchone()[0]
        self.assertEqual(row, ("legacy_unbound", None, "legacy-token-do-not-activate"))
        self.assertEqual(version, issuer.ISSUER_DB_SCHEMA_VERSION)


if __name__ == "__main__":
    unittest.main()
