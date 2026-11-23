from __future__ import annotations

import base64
import hashlib
import json
import tempfile
import unittest
import uuid
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

import issuer


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_device_request() -> tuple[str, str]:
    private_key = ec.generate_private_key(ec.SECP256R1())
    spki = private_key.public_key().public_bytes(
        Encoding.DER,
        PublicFormat.SubjectPublicKeyInfo,
    )
    fingerprint = b64url(hashlib.sha256(spki).digest())
    payload = {
        "schema_version": 1,
        "request_id": str(uuid.uuid4()),
        "nonce": b64url(b"N" * 32),
        "app_id": issuer.APP_ID,
        "product_id": issuer.PRODUCT_ID,
        "issued_at": "2026-11-23T09:00:00Z",
        "device_public_key_spki": b64url(spki),
        "device_key_sha256": fingerprint,
    }
    payload_segment = b64url(issuer._canonical_json(payload))
    message = ("YANJIR1." + payload_segment).encode("ascii")
    signature = private_key.sign(message, ec.ECDSA(hashes.SHA256()))
    return "YANJIR1." + payload_segment + "." + b64url(signature), fingerprint


class IssuerProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / "orders.sqlite3"
        self.issuer_key = ed25519.Ed25519PrivateKey.generate()

    def issue(self, request: str, order_id: str = "YJ-TEST-0001") -> str:
        return issuer.issue_license(
            request_token=request,
            order_id=order_id,
            issuer_key_id="issuer-test-01",
            issuer_private_key=self.issuer_key,
            database_path=self.db,
        )

    def test_valid_request_produces_verifiable_perpetual_license(self) -> None:
        request, fingerprint = make_device_request()
        token = self.issue(request)
        prefix, payload_segment, signature_segment = token.split(".")
        self.assertEqual(prefix, "YANJI1")
        payload = json.loads(issuer._b64url_decode(payload_segment).decode("utf-8"))
        self.assertEqual(payload["product_id"], issuer.PRODUCT_ID)
        self.assertTrue(payload["perpetual"])
        self.assertEqual(payload["device_key_sha256"], fingerprint)
        self.assertEqual(payload["product_revision"], 1)
        self.assertEqual(payload["features"], sorted(issuer.FEATURES))
        signature = issuer._b64url_decode(signature_segment)
        self.issuer_key.public_key().verify(
            signature,
            ("YANJI1." + payload_segment).encode("ascii"),
        )

    def test_same_order_and_same_request_is_idempotent(self) -> None:
        request, _ = make_device_request()
        self.assertEqual(self.issue(request), self.issue(request))

    def test_order_cannot_be_reused_for_another_device(self) -> None:
        first_request, _ = make_device_request()
        second_request, _ = make_device_request()
        self.issue(first_request)
        with self.assertRaises(issuer.IssuerError):
            self.issue(second_request)

    def test_same_request_cannot_be_attached_to_another_order(self) -> None:
        request, _ = make_device_request()
        self.issue(request, "YJ-TEST-0001")
        with self.assertRaises(issuer.IssuerError):
            self.issue(request, "YJ-TEST-0002")

    def test_modified_request_payload_is_rejected(self) -> None:
        request, _ = make_device_request()
        prefix, payload_segment, signature = request.split(".")
        payload = json.loads(issuer._b64url_decode(payload_segment))
        payload["app_id"] = "com.example.other"
        changed_segment = b64url(issuer._canonical_json(payload))
        tampered = prefix + "." + changed_segment + "." + signature
        with self.assertRaises(issuer.IssuerError):
            issuer.verify_device_request(tampered)

    def test_invalid_request_signature_is_rejected(self) -> None:
        request, _ = make_device_request()
        prefix, payload_segment, signature = request.split(".")
        signature_bytes = bytearray(issuer._b64url_decode(signature))
        signature_bytes[-1] ^= 0x01
        tampered = prefix + "." + payload_segment + "." + b64url(bytes(signature_bytes))
        with self.assertRaises(issuer.IssuerError):
            issuer.verify_device_request(tampered)

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with self.assertRaises(issuer.IssuerError):
            issuer._decode_json_object(b'{"schema_version":1,"schema_version":1}')


if __name__ == "__main__":
    unittest.main()
