#!/usr/bin/env python3
"""Offline issuer for Yanji Pro lifetime licenses.

The signing key is encrypted at rest and must remain outside the repository.
This tool records technical order metadata only; it does not collect buyer PII.
"""
from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import json
import os
import re
import sqlite3
import stat
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    PublicFormat,
    PrivateFormat,
    BestAvailableEncryption,
)

APP_ID = "com.nihaisha.nihaisha_app"
PRODUCT_ID = "yanji_pro_lifetime"
PRODUCT_REVISION = 1
LICENSE_PREFIX = "YANJI1"
REQUEST_PREFIX = "YANJIR1"
FEATURES = (
    "advanced_export",
    "advanced_learning",
    "ai_advanced",
    "contextual_assistant",
)
MAX_COMPACT_LENGTH = 16384
ORDER_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$")
KEY_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
BASE64URL_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


class IssuerError(Exception):
    """Expected validation or operator error."""


def _now_utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(value: str, *, max_bytes: int = 8192) -> bytes:
    if (
        not isinstance(value, str)
        or not value
        or len(value) % 4 == 1
        or not BASE64URL_PATTERN.fullmatch(value)
    ):
        raise IssuerError("Malformed base64url segment.")
    padding = "=" * ((4 - len(value) % 4) % 4)
    try:
        decoded = base64.b64decode(
            (value + padding).encode("ascii"),
            altchars=b"-_",
            validate=True,
        )
    except (ValueError, UnicodeEncodeError) as error:
        raise IssuerError("Malformed base64url segment.") from error
    if len(decoded) > max_bytes:
        raise IssuerError("Encoded segment exceeds the size limit.")
    return decoded


def _compact_parts(token: str, expected_prefix: str) -> tuple[str, bytes, bytes]:
    if not isinstance(token, str) or len(token) > MAX_COMPACT_LENGTH:
        raise IssuerError("Compact token is missing or too large.")
    parts = token.strip().split(".")
    if len(parts) != 3 or parts[0] != expected_prefix:
        raise IssuerError("Unsupported compact token format.")
    payload_bytes = _b64url_decode(parts[1])
    signature_bytes = _b64url_decode(parts[2], max_bytes=256)
    if not payload_bytes:
        raise IssuerError("Empty token payload.")
    return parts[1], payload_bytes, signature_bytes


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise IssuerError("Duplicate JSON object key: " + key)
        result[key] = value
    return result


def _decode_json_object(payload_bytes: bytes) -> dict[str, Any]:
    try:
        value = json.loads(
            payload_bytes.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IssuerError("Token payload is not valid UTF-8 JSON.") from error
    if not isinstance(value, dict):
        raise IssuerError("Token payload must be a JSON object.")
    return value


def _canonical_json(value: dict[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def _require_string(data: dict[str, Any], key: str, maximum: int = 256) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise IssuerError("Invalid request field: " + key)
    return value


def verify_device_request(request_token: str) -> dict[str, Any]:
    """Verify a YANJIR1 request and its P-256 proof-of-possession signature."""
    payload_segment, payload_bytes, signature_bytes = _compact_parts(
        request_token, REQUEST_PREFIX
    )
    if len(payload_bytes) > 8192:
        raise IssuerError("Device request payload is too large.")
    data = _decode_json_object(payload_bytes)

    if data.get("schema_version") != 1:
        raise IssuerError("Unsupported device request schema.")
    if _require_string(data, "app_id", 160) != APP_ID:
        raise IssuerError("Device request belongs to another application.")
    if _require_string(data, "product_id", 80) != PRODUCT_ID:
        raise IssuerError("Device request asks for an unsupported product.")

    request_id = _require_string(data, "request_id", 64)
    try:
        if str(uuid.UUID(request_id)) != request_id.lower():
            raise ValueError("non-canonical UUID")
    except ValueError as error:
        raise IssuerError("Invalid request_id.") from error

    nonce = _b64url_decode(_require_string(data, "nonce", 64), max_bytes=64)
    if len(nonce) != 32:
        raise IssuerError("Device request nonce must contain 32 random bytes.")

    issued_at = _require_string(data, "issued_at", 64)
    try:
        parsed_time = datetime.fromisoformat(issued_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise IssuerError("Invalid device request issued_at.") from error
    if parsed_time.tzinfo is None or not issued_at.endswith("Z"):
        raise IssuerError("Device request issued_at must be UTC.")

    spki = _b64url_decode(
        _require_string(data, "device_public_key_spki", 4096),
        max_bytes=2048,
    )
    supplied_fingerprint = _require_string(data, "device_key_sha256", 64)
    computed_fingerprint = _b64url_encode(hashlib.sha256(spki).digest())
    if supplied_fingerprint != computed_fingerprint:
        raise IssuerError("Device public-key fingerprint does not match.")

    try:
        public_key = serialization.load_der_public_key(spki)
    except (ValueError, TypeError) as error:
        raise IssuerError("Invalid device public key.") from error
    if (
        not isinstance(public_key, ec.EllipticCurvePublicKey)
        or not isinstance(public_key.curve, ec.SECP256R1)
    ):
        raise IssuerError("Device key must be an ECDSA P-256 public key.")

    signed_message = (REQUEST_PREFIX + "." + payload_segment).encode("ascii")
    try:
        public_key.verify(
            signature_bytes,
            signed_message,
            ec.ECDSA(hashes.SHA256()),
        )
    except InvalidSignature as error:
        raise IssuerError("Device proof-of-possession signature is invalid.") from error

    return {
        "request_id": request_id,
        "app_id": APP_ID,
        "product_id": PRODUCT_ID,
        "device_key_sha256": computed_fingerprint,
    }


def default_data_dir() -> Path:
    return Path.home() / ".yanji-license-issuer" / "data"


def default_key_dir() -> Path:
    return Path.home() / ".yanji-license-issuer" / "keys"


def default_database_path() -> Path:
    return default_data_dir() / "orders.sqlite3"


def initialize_database(database_path: Path) -> None:
    database_path = Path(database_path)
    database_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with sqlite3.connect(database_path) as connection:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS issued_orders (
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
        connection.commit()
    try:
        os.chmod(database_path.parent, 0o700)
        os.chmod(database_path, stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        # Windows ACLs are not expressed by chmod; use account-level ACLs.
        pass


def issue_license(
    *,
    request_token: str,
    order_id: str,
    issuer_key_id: str,
    issuer_private_key: ed25519.Ed25519PrivateKey,
    database_path: Path,
) -> str:
    if not ORDER_ID_PATTERN.fullmatch(order_id):
        raise IssuerError("Invalid order id.")
    if not KEY_ID_PATTERN.fullmatch(issuer_key_id):
        raise IssuerError("Invalid issuer key id.")
    if not isinstance(issuer_private_key, ed25519.Ed25519PrivateKey):
        raise IssuerError("Issuer private key must be Ed25519.")

    request = verify_device_request(request_token)
    issued_at = _now_utc()
    initialize_database(Path(database_path))

    with sqlite3.connect(database_path) as connection:
        existing = connection.execute(
            """
            SELECT request_id, device_key_sha256, license_token
            FROM issued_orders WHERE order_id = ?
            """,
            (order_id,),
        ).fetchone()
        if existing is not None:
            if (
                existing[0] == request["request_id"]
                and existing[1] == request["device_key_sha256"]
            ):
                return str(existing[2])
            raise IssuerError("Order id already belongs to a different request.")

        duplicate_request = connection.execute(
            "SELECT order_id FROM issued_orders WHERE request_id = ?",
            (request["request_id"],),
        ).fetchone()
        if duplicate_request is not None:
            raise IssuerError("This device request has already been issued.")

        payload = {
            "schema_version": 1,
            "license_id": "LIC-" + str(uuid.uuid4()),
            "order_id": order_id,
            "product_id": PRODUCT_ID,
            "product_revision": PRODUCT_REVISION,
            "app_id": APP_ID,
            "perpetual": True,
            "features": list(FEATURES),
            "device_key_sha256": request["device_key_sha256"],
            "issued_at": issued_at,
            "issuer_key_id": issuer_key_id,
        }
        payload_segment = _b64url_encode(_canonical_json(payload))
        signed_message = (LICENSE_PREFIX + "." + payload_segment).encode("ascii")
        signature = issuer_private_key.sign(signed_message)
        token = LICENSE_PREFIX + "." + payload_segment + "." + _b64url_encode(signature)

        # Verify the signature before committing the immutable order record.
        issuer_private_key.public_key().verify(signature, signed_message)
        connection.execute(
            """
            INSERT INTO issued_orders (
                order_id, request_id, license_id, product_id,
                device_key_sha256, issuer_key_id, issued_at, license_token
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                order_id,
                request["request_id"],
                payload["license_id"],
                PRODUCT_ID,
                request["device_key_sha256"],
                issuer_key_id,
                issued_at,
                token,
            ),
        )
        connection.commit()
    return token


def load_private_key(path: Path, password: bytes) -> ed25519.Ed25519PrivateKey:
    try:
        key = serialization.load_pem_private_key(Path(path).read_bytes(), password=password)
    except (ValueError, TypeError) as error:
        raise IssuerError("Cannot load issuer key; check passphrase.") from error
    if not isinstance(key, ed25519.Ed25519PrivateKey):
        raise IssuerError("Issuer key file is not Ed25519.")
    return key


def generate_keypair(key_dir: Path, key_id: str) -> tuple[Path, Path, str]:
    if not KEY_ID_PATTERN.fullmatch(key_id):
        raise IssuerError("Invalid issuer key id.")
    key_dir = Path(key_dir).expanduser()
    key_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    private_path = key_dir / (key_id + ".private.pem")
    public_path = key_dir / (key_id + ".public.pem")
    if private_path.exists() or public_path.exists():
        raise IssuerError("Key files already exist; refusing to overwrite.")

    passphrase = getpass.getpass("New issuer private-key passphrase: ").encode("utf-8")
    confirmation = getpass.getpass("Repeat passphrase: ").encode("utf-8")
    if len(passphrase) < 12 or passphrase != confirmation:
        raise IssuerError("Passphrase must be at least 12 bytes and match.")

    private_key = ed25519.Ed25519PrivateKey.generate()
    private_bytes = private_key.private_bytes(
        Encoding.PEM,
        PrivateFormat.PKCS8,
        BestAvailableEncryption(passphrase),
    )
    public_key = private_key.public_key()
    public_bytes = public_key.public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    raw_public = public_key.public_bytes(Encoding.Raw, PublicFormat.Raw)

    private_path.write_bytes(private_bytes)
    public_path.write_bytes(public_bytes)
    try:
        os.chmod(key_dir, 0o700)
        os.chmod(private_path, stat.S_IRUSR | stat.S_IWUSR)
        os.chmod(public_path, stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        pass
    return private_path, public_path, _b64url_encode(raw_public)


def list_orders(database_path: Path) -> list[tuple[Any, ...]]:
    if not Path(database_path).exists():
        return []
    with sqlite3.connect(database_path) as connection:
        return connection.execute(
            """
            SELECT order_id, license_id, product_id, device_key_sha256,
                   issuer_key_id, issued_at
            FROM issued_orders ORDER BY issued_at DESC
            """
        ).fetchall()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Offline issuer for Yanji Pro perpetual licenses."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    keygen = subparsers.add_parser("keygen", help="Generate an encrypted Ed25519 issuer key.")
    keygen.add_argument("--key-id", required=True)
    keygen.add_argument("--key-dir", type=Path, default=default_key_dir())

    issue = subparsers.add_parser("issue", help="Issue after manual payment confirmation.")
    issue.add_argument("--request-file", type=Path, required=True)
    issue.add_argument("--order-id", required=True)
    issue.add_argument("--key-id", required=True)
    issue.add_argument("--private-key", type=Path, required=True)
    issue.add_argument("--db", type=Path, default=default_database_path())
    issue.add_argument("--out", type=Path)
    issue.add_argument(
        "--payment-confirmed",
        action="store_true",
        required=True,
        help="Operator attests that payment has been checked.",
    )

    listing = subparsers.add_parser("list", help="List technical order records.")
    listing.add_argument("--db", type=Path, default=default_database_path())
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "keygen":
            private_path, public_path, raw_public = generate_keypair(
                args.key_dir, args.key_id
            )
            print("Issuer key id: " + args.key_id)
            print("Private key: " + str(private_path))
            print("Public key: " + str(public_path))
            print("Public key raw base64url: " + raw_public)
            print("Keep the private key outside the repository and back it up offline.")
            return 0

        if args.command == "issue":
            request_token = args.request_file.read_text(encoding="utf-8").strip()
            passphrase = getpass.getpass("Issuer private-key passphrase: ").encode("utf-8")
            private_key = load_private_key(args.private_key, passphrase)
            token = issue_license(
                request_token=request_token,
                order_id=args.order_id,
                issuer_key_id=args.key_id,
                issuer_private_key=private_key,
                database_path=args.db,
            )
            if args.out:
                output_path = args.out.expanduser()
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_text(token + "\n", encoding="utf-8")
                try:
                    os.chmod(output_path, stat.S_IRUSR | stat.S_IWUSR)
                except OSError:
                    pass
                print("License token written to: " + str(output_path))
            else:
                print(token)
            return 0

        if args.command == "list":
            for row in list_orders(args.db):
                print(" | ".join(str(value) for value in row))
            return 0
        parser.error("Unsupported command.")
    except (IssuerError, OSError, sqlite3.Error) as error:
        print("ISSUER ERROR: " + str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
