#!/usr/bin/env python3
"""Offline issuer for Yanji Pro lifetime licenses.

All private signing keys stay outside the repository. The local SQLite database
stores order-to-license history and operational audit events, not buyer PII.
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
import tempfile
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
PROTOCOL_REVISION = 1
LICENSE_PREFIX = "YANJI1"
LICENSE_SIGNATURE_DOMAIN = b"YANJI-PRO-LICENSE-V1\x00"
REQUEST_PREFIX = "YANJIR1"
KNOWN_FEATURE_IDS = frozenset({
    "advanced_export",
    "advanced_learning",
    "ai_advanced",
    "contextual_assistant",
})
PROTOCOL_ALLOWED_FEATURES_BY_REVISION = {
    1: frozenset({"ai_advanced", "contextual_assistant"}),
}
DEFAULT_PRO_FEATURES = ("ai_advanced", "contextual_assistant")
ISSUABLE_FEATURES_BY_REVISION = {
    1: DEFAULT_PRO_FEATURES,
}
DEVICE_SECURITY_LEVELS = {
    "SOFTWARE",
    "TRUSTED_ENVIRONMENT",
    "STRONGBOX",
    "UNKNOWN",
}
ISSUER_KEYRING_SCHEMA_VERSION = 1
ISSUER_DB_SCHEMA_VERSION = 2
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
    normalized = token.strip()
    parts = normalized.split(".")
    if len(parts) != 3 or parts[0] != expected_prefix:
        raise IssuerError("Unsupported compact token format.")
    payload_bytes = _b64url_decode(parts[1], max_bytes=12288)
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


def _parse_utc(value: str, field: str) -> None:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise IssuerError("Invalid UTC timestamp: " + field) from error
    if parsed.tzinfo is None or not value.endswith("Z"):
        raise IssuerError(field + " must be an ISO-8601 UTC value.")


def verify_device_request(request_token: str) -> dict[str, Any]:
    """Verify a YANJIR1 request and its P-256 proof-of-possession signature."""
    normalized_token = request_token.strip()
    payload_segment, payload_bytes, signature_bytes = _compact_parts(
        normalized_token, REQUEST_PREFIX
    )
    if len(payload_bytes) > 8192:
        raise IssuerError("Device request payload is too large.")
    if len(signature_bytes) < 8 or len(signature_bytes) > 80:
        raise IssuerError("Device request ECDSA signature length is invalid.")
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

    nonce_text = _require_string(data, "request_nonce", 64)
    nonce = _b64url_decode(nonce_text, max_bytes=64)
    if len(nonce) != 32:
        raise IssuerError("Device request nonce must contain 32 random bytes.")

    issued_at = _require_string(data, "issued_at", 64)
    _parse_utc(issued_at, "issued_at")

    security_level = _require_string(data, "device_key_security_level", 32)
    if security_level not in DEVICE_SECURITY_LEVELS:
        raise IssuerError("Unsupported reported device security level.")

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
    canonical_spki = public_key.public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
    if canonical_spki != spki:
        raise IssuerError("Device public key is not canonical SPKI DER.")

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
        "request_nonce": nonce_text,
        "request_sha256": _b64url_encode(
            hashlib.sha256(normalized_token.encode("ascii")).digest()
        ),
        "app_id": APP_ID,
        "product_id": PRODUCT_ID,
        "device_key_sha256": computed_fingerprint,
        "device_key_security_level": security_level,
    }


def default_root_dir() -> Path:
    return Path.home() / ".yanji-license-issuer"


def default_data_dir() -> Path:
    return default_root_dir() / "data"


def default_key_dir() -> Path:
    return default_root_dir() / "keys"


def default_database_path() -> Path:
    return default_data_dir() / "orders.sqlite3"


def default_keyring_path() -> Path:
    return default_key_dir() / "issuer-keyring.json"


def _atomic_write(path: Path, data: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=path.parent,
    )
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.chmod(temporary_name, mode)
        except OSError:
            pass
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise


def load_issuer_keyring(keyring_path: Path) -> dict[str, dict[str, Any]]:
    keyring_path = Path(keyring_path).expanduser()
    try:
        raw = keyring_path.read_bytes()
    except OSError as error:
        raise IssuerError("Issuer keyring file is missing or unreadable.") from error
    data = _decode_json_object(raw)
    if data.get("schema_version") != ISSUER_KEYRING_SCHEMA_VERSION:
        raise IssuerError("Unsupported issuer keyring schema.")
    keys = data.get("keys")
    if not isinstance(keys, dict):
        raise IssuerError("Issuer keyring keys must be a JSON object.")

    result: dict[str, dict[str, Any]] = {}
    for key_id, entry in keys.items():
        if not isinstance(key_id, str) or not KEY_ID_PATTERN.fullmatch(key_id):
            raise IssuerError("Invalid issuer key id in keyring.")
        if not isinstance(entry, dict):
            raise IssuerError("Invalid issuer keyring entry.")
        status = entry.get("status")
        if status not in {"active", "retired", "compromised"}:
            raise IssuerError("Invalid issuer key status.")
        raw_public = _b64url_decode(
            _require_string(entry, "public_key_raw_base64url", 64),
            max_bytes=32,
        )
        if len(raw_public) != 32:
            raise IssuerError("Ed25519 public key must contain 32 bytes.")
        result[key_id] = {"status": status, "public_key": raw_public}
    return result


def _table_exists(connection: sqlite3.Connection, table_name: str) -> bool:
    row = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,),
    ).fetchone()
    return row is not None


def _audit_event(
    connection: sqlite3.Connection,
    *,
    order_id: str,
    license_id: str | None,
    event_type: str,
    details: dict[str, Any],
) -> None:
    connection.execute(
        """
        INSERT INTO issuer_audit_events (
            event_id, order_id, license_id, event_type, occurred_at, details_json
        ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            str(uuid.uuid4()),
            order_id,
            license_id,
            event_type,
            _now_utc(),
            json.dumps(details, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        ),
    )


def initialize_database(database_path: Path) -> None:
    database_path = Path(database_path).expanduser()
    database_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with sqlite3.connect(database_path) as connection:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 5000")
        connection.execute("BEGIN IMMEDIATE")

        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS orders (
                order_id TEXT PRIMARY KEY,
                product_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                payment_status TEXT NOT NULL DEFAULT 'confirmed',
                reissue_count INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS issued_licenses (
                license_id TEXT PRIMARY KEY,
                order_id TEXT NOT NULL,
                request_id TEXT NOT NULL UNIQUE,
                request_sha256 TEXT,
                request_nonce TEXT,
                device_key_sha256 TEXT NOT NULL,
                device_key_security_level TEXT,
                issuer_key_id TEXT NOT NULL,
                issued_at TEXT NOT NULL,
                license_token TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                reissue_sequence INTEGER NOT NULL DEFAULT 0,
                replacement_for_license_id TEXT,
                replaced_by_license_id TEXT,
                status_changed_at TEXT,
                status_reason TEXT,
                FOREIGN KEY(order_id) REFERENCES orders(order_id),
                UNIQUE(order_id, reissue_sequence)
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS issuer_audit_events (
                event_id TEXT PRIMARY KEY,
                order_id TEXT NOT NULL,
                license_id TEXT,
                event_type TEXT NOT NULL,
                occurred_at TEXT NOT NULL,
                details_json TEXT NOT NULL,
                FOREIGN KEY(order_id) REFERENCES orders(order_id)
            )
            """
        )

        # Preserve pre-v2 local issuer records. They are marked legacy_unbound
        # because their old tokens lack request_id/nonce/hash binding.
        if _table_exists(connection, "issued_orders") and not _table_exists(
            connection, "issuer_v2_legacy_migrated"
        ):
            old_rows = connection.execute(
                """
                SELECT order_id, request_id, license_id, product_id,
                       device_key_sha256, issuer_key_id, issued_at, license_token
                FROM issued_orders
                """
            ).fetchall()
            for row in old_rows:
                order_id, request_id, license_id, product_id, fingerprint, key_id, issued_at, token = row
                connection.execute(
                    """
                    INSERT OR IGNORE INTO orders (
                        order_id, product_id, created_at, payment_status, reissue_count
                    ) VALUES (?, ?, ?, 'confirmed', 0)
                    """,
                    (order_id, product_id, issued_at),
                )
                connection.execute(
                    """
                    INSERT OR IGNORE INTO issued_licenses (
                        license_id, order_id, request_id, request_sha256,
                        request_nonce, device_key_sha256, issuer_key_id,
                        issued_at, license_token, status, reissue_sequence,
                        status_reason
                    ) VALUES (?, ?, ?, NULL, NULL, ?, ?, ?, ?, 'legacy_unbound', 0,
                              'Migrated from pre-v2 issuer; not eligible for production activation')
                    """,
                    (license_id, order_id, request_id, fingerprint, key_id, issued_at, token),
                )
                _audit_event(
                    connection,
                    order_id=order_id,
                    license_id=license_id,
                    event_type="legacy_record_migrated",
                    details={"source": "issued_orders", "binding": "legacy_unbound"},
                )
            connection.execute(
                "CREATE TABLE IF NOT EXISTS issuer_v2_legacy_migrated (id INTEGER PRIMARY KEY CHECK (id=1))"
            )
            connection.execute(
                "INSERT OR IGNORE INTO issuer_v2_legacy_migrated(id) VALUES (1)"
            )

        connection.execute("PRAGMA user_version = 2")
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
    issuer_public_key: ed25519.Ed25519PublicKey,
    issuer_key_status: str,
    database_path: Path,
    reissue: bool = False,
    reissue_reason: str | None = None,
) -> str:
    if not ORDER_ID_PATTERN.fullmatch(order_id):
        raise IssuerError("Invalid order id.")
    if not KEY_ID_PATTERN.fullmatch(issuer_key_id):
        raise IssuerError("Invalid issuer key id.")
    if issuer_key_status != "active":
        raise IssuerError("Only an active issuer key may sign new licenses.")
    if not isinstance(issuer_private_key, ed25519.Ed25519PrivateKey):
        raise IssuerError("Issuer private key must be Ed25519.")
    if not isinstance(issuer_public_key, ed25519.Ed25519PublicKey):
        raise IssuerError("Issuer public key must be Ed25519.")
    private_raw = issuer_private_key.public_key().public_bytes(
        Encoding.Raw, PublicFormat.Raw
    )
    public_raw = issuer_public_key.public_bytes(Encoding.Raw, PublicFormat.Raw)
    if private_raw != public_raw:
        raise IssuerError("Issuer private key does not match the public key registered to this key id.")
    if reissue and not (reissue_reason and reissue_reason.strip()):
        raise IssuerError("A non-empty --reason is required for reissue.")
    if not reissue and reissue_reason:
        raise IssuerError("--reason is only valid with --reissue.")

    request = verify_device_request(request_token)
    issued_at = _now_utc()
    initialize_database(Path(database_path))

    with sqlite3.connect(database_path) as connection:
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 5000")
        connection.execute("BEGIN IMMEDIATE")

        existing_request = connection.execute(
            """
            SELECT order_id, request_sha256, license_token, status
            FROM issued_licenses
            WHERE request_id = ?
            """,
            (request["request_id"],),
        ).fetchone()
        if existing_request is not None:
            if (
                existing_request["order_id"] == order_id
                and existing_request["request_sha256"] == request["request_sha256"]
                and existing_request["status"] == "active"
            ):
                connection.commit()
                return str(existing_request["license_token"])
            raise IssuerError("This request id has already been consumed; create a new device request.")

        order = connection.execute(
            "SELECT payment_status, reissue_count FROM orders WHERE order_id = ?",
            (order_id,),
        ).fetchone()
        if order is None:
            if reissue:
                raise IssuerError("Cannot reissue: the order has no prior issuance record.")
            connection.execute(
                """
                INSERT INTO orders (order_id, product_id, created_at, payment_status, reissue_count)
                VALUES (?, ?, ?, 'confirmed', 0)
                """,
                (order_id, PRODUCT_ID, issued_at),
            )
            reissue_sequence = 0
            previous_license_id = None
            event_type = "license_issued"
        else:
            if order["payment_status"] != "confirmed":
                raise IssuerError("Order is not in confirmed payment status.")
            if not reissue:
                raise IssuerError(
                    "Order already exists. Use --reissue with a new request and documented reason."
                )
            previous = connection.execute(
                """
                SELECT license_id FROM issued_licenses
                WHERE order_id = ? AND status = 'active'
                ORDER BY reissue_sequence DESC LIMIT 1
                """,
                (order_id,),
            ).fetchone()
            previous_license_id = (
                str(previous["license_id"]) if previous is not None else None
            )
            maximum = connection.execute(
                "SELECT COALESCE(MAX(reissue_sequence), -1) FROM issued_licenses WHERE order_id = ?",
                (order_id,),
            ).fetchone()[0]
            reissue_sequence = int(maximum) + 1
            event_type = "license_reissued"

        issuable_features = ISSUABLE_FEATURES_BY_REVISION.get(PROTOCOL_REVISION)
        protocol_allowed = PROTOCOL_ALLOWED_FEATURES_BY_REVISION.get(PROTOCOL_REVISION)
        if (
            not issuable_features
            or protocol_allowed is None
            or not set(issuable_features).issubset(KNOWN_FEATURE_IDS)
            or not set(issuable_features).issubset(protocol_allowed)
        ):
            raise IssuerError(
                "Issuer features exceed the protocol-allowed set for this revision."
            )
        payload = {
            "schema_version": 1,
            "license_id": "LIC-" + str(uuid.uuid4()),
            "order_id": order_id,
            "product_id": PRODUCT_ID,
            "protocol_revision": PROTOCOL_REVISION,
            "app_id": APP_ID,
            "perpetual": True,
            "features": sorted(issuable_features),
            "device_public_key_sha256": request["device_key_sha256"],
            "request_id": request["request_id"],
            "issued_at": issued_at,
            "issuer_key_id": issuer_key_id,
        }
        payload_segment = _b64url_encode(_canonical_json(payload))
        signed_message = LICENSE_SIGNATURE_DOMAIN + _canonical_json(payload)
        signature = issuer_private_key.sign(signed_message)
        token = LICENSE_PREFIX + "." + payload_segment + "." + _b64url_encode(signature)

        # Verify the just-created signature and device/request linkage before commit.
        issuer_public_key.verify(signature, signed_message)
        if previous_license_id is not None:
            connection.execute(
                """
                UPDATE issued_licenses
                SET status = 'superseded', replaced_by_license_id = ?,
                    status_changed_at = ?, status_reason = ?
                WHERE license_id = ? AND status = 'active'
                """,
                (
                    payload["license_id"],
                    issued_at,
                    reissue_reason.strip() if reissue_reason else "Reissued for a new device request",
                    previous_license_id,
                ),
            )
        connection.execute(
            """
            INSERT INTO issued_licenses (
                license_id, order_id, request_id, request_sha256, request_nonce,
                device_key_sha256, device_key_security_level, issuer_key_id,
                issued_at, license_token, status, reissue_sequence,
                replacement_for_license_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
            """,
            (
                payload["license_id"],
                order_id,
                request["request_id"],
                request["request_sha256"],
                request["request_nonce"],
                request["device_key_sha256"],
                request["device_key_security_level"],
                issuer_key_id,
                issued_at,
                token,
                reissue_sequence,
                previous_license_id,
            ),
        )
        if reissue:
            connection.execute(
                "UPDATE orders SET reissue_count = reissue_count + 1 WHERE order_id = ?",
                (order_id,),
            )
        _audit_event(
            connection,
            order_id=order_id,
            license_id=payload["license_id"],
            event_type=event_type,
            details={
                "request_id": request["request_id"],
                "request_sha256": request["request_sha256"],
                "device_key_sha256": request["device_key_sha256"],
                "issuer_key_id": issuer_key_id,
                "reissue_sequence": reissue_sequence,
                "replaced_license_id": previous_license_id,
                "reason": reissue_reason.strip() if reissue_reason else None,
            },
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


def generate_keypair(
    key_dir: Path,
    key_id: str,
    keyring_path: Path | None = None,
) -> tuple[Path, Path, str]:
    if not KEY_ID_PATTERN.fullmatch(key_id):
        raise IssuerError("Invalid issuer key id.")
    key_dir = Path(key_dir).expanduser()
    key_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    keyring_path = Path(keyring_path or (key_dir / "issuer-keyring.json")).expanduser()
    private_path = key_dir / (key_id + ".private.pem")
    public_path = key_dir / (key_id + ".public.pem")
    if private_path.exists() or public_path.exists():
        raise IssuerError("Key files already exist; refusing to overwrite.")

    existing_keys: dict[str, dict[str, Any]] = {}
    if keyring_path.exists():
        existing_keys = load_issuer_keyring(keyring_path)
    if key_id in existing_keys:
        raise IssuerError("Key id already exists in issuer keyring.")

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
    raw_public_b64url = _b64url_encode(raw_public)

    _atomic_write(private_path, private_bytes, mode=0o600)
    _atomic_write(public_path, public_bytes, mode=0o600)
    existing_keys[key_id] = {
        "status": "active",
        "public_key_raw_base64url": raw_public_b64url,
    }
    keyring_document = {
        "schema_version": ISSUER_KEYRING_SCHEMA_VERSION,
        "keys": existing_keys,
    }
    _atomic_write(
        keyring_path,
        json.dumps(keyring_document, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8") + b"\n",
        mode=0o600,
    )
    try:
        os.chmod(key_dir, 0o700)
    except OSError:
        pass
    return private_path, public_path, raw_public_b64url


def list_orders(database_path: Path) -> list[tuple[Any, ...]]:
    if not Path(database_path).exists():
        return []
    initialize_database(database_path)
    with sqlite3.connect(database_path) as connection:
        return connection.execute(
            """
            SELECT l.order_id, l.license_id, l.status, o.product_id,
                   l.device_key_sha256, l.issuer_key_id, l.issued_at,
                   l.reissue_sequence, l.replaced_by_license_id
            FROM issued_licenses AS l
            INNER JOIN orders AS o ON o.order_id = l.order_id
            ORDER BY l.issued_at DESC, l.reissue_sequence DESC
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
    keygen.add_argument("--keyring", type=Path, default=default_keyring_path())

    issue = subparsers.add_parser("issue", help="Issue after manual payment confirmation.")
    issue.add_argument("--request-file", type=Path, required=True)
    issue.add_argument("--order-id", required=True)
    issue.add_argument("--key-id", required=True)
    issue.add_argument("--private-key", type=Path, required=True)
    issue.add_argument("--keyring", type=Path, default=default_keyring_path())
    issue.add_argument("--db", type=Path, default=default_database_path())
    issue.add_argument("--out", type=Path)
    issue.add_argument("--reissue", action="store_true")
    issue.add_argument("--reason")
    issue.add_argument(
        "--payment-confirmed",
        action="store_true",
        required=True,
        help="Operator attests that payment has been checked.",
    )

    listing = subparsers.add_parser("list", help="List technical order/license records.")
    listing.add_argument("--db", type=Path, default=default_database_path())
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "keygen":
            private_path, public_path, raw_public = generate_keypair(
                args.key_dir,
                args.key_id,
                args.keyring,
            )
            print("Issuer key id: " + args.key_id)
            print("Private key: " + str(private_path))
            print("Public key: " + str(public_path))
            print("Public key raw base64url: " + raw_public)
            print("Keyring: " + str(args.keyring))
            print("Keep at least two encrypted offline backups in separate locations.")
            return 0

        if args.command == "issue":
            request_token = args.request_file.read_text(encoding="utf-8").strip()
            passphrase = getpass.getpass("Issuer private-key passphrase: ").encode("utf-8")
            private_key = load_private_key(args.private_key, passphrase)
            keyring = load_issuer_keyring(args.keyring)
            entry = keyring.get(args.key_id)
            if entry is None:
                raise IssuerError("issuer_key_id is not registered in the local keyring.")
            public_key = ed25519.Ed25519PublicKey.from_public_bytes(entry["public_key"])
            token = issue_license(
                request_token=request_token,
                order_id=args.order_id,
                issuer_key_id=args.key_id,
                issuer_private_key=private_key,
                issuer_public_key=public_key,
                issuer_key_status=entry["status"],
                database_path=args.db,
                reissue=args.reissue,
                reissue_reason=args.reason,
            )
            if args.out:
                output_path = args.out.expanduser()
                output_path.parent.mkdir(parents=True, exist_ok=True)
                _atomic_write(output_path, (token + "\n").encode("utf-8"), mode=0o600)
                print("License token written to: " + str(output_path))
            else:
                print(token)
            return 0

        if args.command == "list":
            for row in list_orders(args.db):
                print(" | ".join(str(value) for value in row))
            return 0
        parser.error("Unsupported command.")
    except (IssuerError, OSError, sqlite3.Error, InvalidSignature) as error:
        print("ISSUER ERROR: " + str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
