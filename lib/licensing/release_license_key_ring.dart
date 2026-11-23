import 'dart:convert';

import 'license_verifier.dart';

const yanjiReleaseLicenseKeyRingEnvironment =
    'YANJI_RELEASE_LICENSE_KEY_RING_JSON';

/// Builds the Release verifier trust anchors from a public-key-only,
/// compile-time configuration. No private signing material belongs in the app.
class ReleaseLicenseKeyRingFactory {
  ReleaseLicenseKeyRingFactory._();

  static const int _schemaVersion = 1;
  static const int _maximumKeys = 16;
  static const String _environmentJson = String.fromEnvironment(
    yanjiReleaseLicenseKeyRingEnvironment,
    defaultValue: '',
  );

  /// Release requires at least one real production issuer trust anchor.
  /// Debug/Test callers may deliberately construct an empty ring, which
  /// preserves unknown-issuer / fail-closed behavior.
  static LicenseKeyRing fromEnvironment({required bool release}) =>
      fromJson(_environmentJson, requireProductionTrustAnchor: release);

  static LicenseKeyRing fromJson(
    String source, {
    required bool requireProductionTrustAnchor,
  }) {
    if (source.trim().isEmpty) {
      if (requireProductionTrustAnchor) {
        throw StateError(
          '$yanjiReleaseLicenseKeyRingEnvironment is required for Release.',
        );
      }
      return LicenseKeyRing(keys: const <LicenseIssuerKey>[]);
    }

    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Release Key Ring must be a JSON object.');
    }
    final root = Map<String, Object?>.from(decoded);
    if (root.keys.toSet().difference(const {'schema_version', 'keys'}).isNotEmpty ||
        root['schema_version'] != _schemaVersion) {
      throw const FormatException('Unsupported Release Key Ring schema.');
    }

    final rawKeys = root['keys'];
    if (rawKeys is! List ||
        rawKeys.isEmpty ||
        rawKeys.length > _maximumKeys) {
      throw const FormatException(
        'Release Key Ring must contain between 1 and 16 issuer keys.',
      );
    }

    final keys = <LicenseIssuerKey>[];
    final ids = <String>{};
    var hasTrustedKey = false;
    for (final raw in rawKeys) {
      if (raw is! Map) {
        throw const FormatException('Issuer key entry must be an object.');
      }
      final entry = Map<String, Object?>.from(raw);
      if (entry.keys.toSet().difference(
            const {'issuer_key_id', 'public_key_base64url', 'status'},
          ).isNotEmpty) {
        throw const FormatException('Issuer key entry contains unknown fields.');
      }

      final keyId = entry['issuer_key_id'];
      final encodedPublicKey = entry['public_key_base64url'];
      final statusName = entry['status'];
      if (keyId is! String ||
          !RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(keyId) ||
          !ids.add(keyId)) {
        throw const FormatException('Issuer key ID is invalid or duplicated.');
      }
      if (requireProductionTrustAnchor &&
          !RegExp(r'^issuer-[0-9]{4}-[0-9]{2}$').hasMatch(keyId)) {
        throw const FormatException(
          'Release Key Ring may contain only production issuer IDs.',
        );
      }
      if (encodedPublicKey is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(encodedPublicKey)) {
        throw const FormatException('Issuer public key must be canonical Base64URL.');
      }

      late final List<int> publicKey;
      try {
        final padded = encodedPublicKey.padRight(
          encodedPublicKey.length + ((4 - encodedPublicKey.length % 4) % 4),
          '=',
        );
        publicKey = base64Url.decode(padded);
      } on FormatException {
        throw const FormatException('Issuer public key Base64URL is invalid.');
      }
      if (publicKey.length != 32 ||
          base64UrlEncode(publicKey).replaceAll('=', '') != encodedPublicKey) {
        throw const FormatException(
          'Issuer public key must decode to exactly 32 canonical bytes.',
        );
      }

      if (statusName is! String) {
        throw const FormatException('Issuer key status is required.');
      }
      final status = switch (statusName) {
        'active' => LicenseIssuerKeyStatus.active,
        'standby' => LicenseIssuerKeyStatus.standby,
        'retired' => LicenseIssuerKeyStatus.retired,
        'revoked' => LicenseIssuerKeyStatus.revoked,
        'compromised' => LicenseIssuerKeyStatus.compromised,
        _ => throw const FormatException('Unknown issuer key status.'),
      };
      final key = LicenseIssuerKey(
        keyId: keyId,
        publicKey: publicKey,
        status: status,
      );
      if (key.mayVerify) hasTrustedKey = true;
      keys.add(key);
    }

    if (requireProductionTrustAnchor && !hasTrustedKey) {
      throw const FormatException(
        'Release Key Ring requires at least one active, standby or retired trust anchor.',
      );
    }

    return LicenseKeyRing(keys: keys);
  }
}
