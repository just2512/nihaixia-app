import 'dart:convert';

import 'license_verifier.dart';

/// Loads only public issuer keys. Private issuer material is never accepted.
///
/// Release builds receive this JSON through the YANJI_LICENSE_KEY_RING
/// Dart define. The Android Gradle Release gate independently validates that
/// the same define is present, non-empty and does not contain test trust.
class LicenseKeyRingFactory {
  LicenseKeyRingFactory._();

  static const String _environmentValue = String.fromEnvironment(
    'YANJI_LICENSE_KEY_RING',
    defaultValue: '',
  );

  /// Empty configuration deliberately creates an empty, fail-closed ring.
  /// This keeps free features available when no production trust anchor has
  /// been configured; no token can verify until a trusted public key is added.
  static LicenseKeyRing fromEnvironment({String? serialized}) {
    final source = serialized ?? _environmentValue;
    if (source.trim().isEmpty) {
      return LicenseKeyRing(keys: const []);
    }
    try {
      return fromJson(source);
    } on FormatException {
      // A malformed build-time configuration never prevents the free app
      // from starting; it simply trusts no issuer. The Release Gradle gate
      // rejects malformed configuration before producing a distributable.
      return LicenseKeyRing(keys: const []);
    } on ArgumentError {
      return LicenseKeyRing(keys: const []);
    }
  }

  /// Strict JSON contract:
  /// {"keys":[{"key_id":"...","public_key_base64url":"...","status":"active"}]}
  static LicenseKeyRing fromJson(String source) {
    if (source.trim().isEmpty) {
      throw const FormatException('License Key Ring configuration is empty.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('License Key Ring configuration is not valid JSON.');
    }
    if (decoded is! Map<String, Object?> ||
        decoded.keys.length != 1 ||
        !decoded.containsKey('keys')) {
      throw const FormatException(
        'License Key Ring configuration must contain only a keys array.',
      );
    }

    final rawKeys = decoded['keys'];
    if (rawKeys is! List) {
      throw const FormatException('License Key Ring keys must be an array.');
    }

    final keys = <LicenseIssuerKey>[];
    for (final rawKey in rawKeys) {
      if (rawKey is! Map<String, Object?> ||
          rawKey.length != 3 ||
          !rawKey.containsKey('key_id') ||
          !rawKey.containsKey('public_key_base64url') ||
          !rawKey.containsKey('status')) {
        throw const FormatException(
          'Each issuer key must contain exactly key_id, public_key_base64url and status.',
        );
      }

      final keyId = rawKey['key_id'];
      final encodedPublicKey = rawKey['public_key_base64url'];
      final rawStatus = rawKey['status'];
      if (keyId is! String ||
          encodedPublicKey is! String ||
          rawStatus is! String) {
        throw const FormatException('Issuer key fields must be strings.');
      }

      final publicKey = _decodePublicKey(encodedPublicKey);
      keys.add(
        LicenseIssuerKey(
          keyId: keyId,
          publicKey: publicKey,
          status: _parseStatus(rawStatus),
        ),
      );
    }
    return LicenseKeyRing(keys: keys);
  }

  static List<int> _decodePublicKey(String encoded) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(encoded)) {
      throw const FormatException(
        'Ed25519 public keys must be 32-byte unpadded Base64URL values.',
      );
    }
    try {
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final decoded = base64Url.decode(padded);
      if (decoded.length != 32 ||
          base64UrlEncode(decoded).replaceAll('=', '') != encoded) {
        throw const FormatException('Invalid Ed25519 public key encoding.');
      }
      return decoded;
    } on FormatException {
      throw const FormatException('Invalid Ed25519 public key encoding.');
    }
  }

  static LicenseIssuerKeyStatus _parseStatus(String value) {
    return switch (value) {
      'active' => LicenseIssuerKeyStatus.active,
      'standby' => LicenseIssuerKeyStatus.standby,
      'retired' => LicenseIssuerKeyStatus.retired,
      'revoked' => LicenseIssuerKeyStatus.revoked,
      'compromised' => LicenseIssuerKeyStatus.compromised,
      _ => throw const FormatException('Unknown issuer key status.'),
    };
  }
}
