import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'license_model.dart';

const _licenseTokenPrefix = 'YANJI1';
const _licenseSignatureDomain = 'YANJI-PRO-LICENSE-V1\u0000';
const _maxLicenseTokenLength = 16384;
const _maxLicensePayloadLength = 12288;

enum LicenseIssuerKeyStatus {
  active,
  standby,
  retired,
  revoked,
  compromised,
}

class LicenseIssuerKey {
  LicenseIssuerKey({
    required this.keyId,
    required List<int> publicKey,
    required this.status,
  }) : publicKey = List<int>.unmodifiable(publicKey) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(keyId)) {
      throw ArgumentError.value(keyId, 'keyId');
    }
  }

  final String keyId;
  final List<int> publicKey;
  final LicenseIssuerKeyStatus status;

  bool get mayVerify => status == LicenseIssuerKeyStatus.active ||
      status == LicenseIssuerKeyStatus.standby ||
      status == LicenseIssuerKeyStatus.retired;
}

class LicenseKeyRing {
  LicenseKeyRing({required Iterable<LicenseIssuerKey> keys})
      : _keys = _buildMap(keys);

  final Map<String, LicenseIssuerKey> _keys;

  LicenseIssuerKey? operator [](String keyId) => _keys[keyId];

  Set<String> get keyIds => Set<String>.unmodifiable(_keys.keys);

  static Map<String, LicenseIssuerKey> _buildMap(
    Iterable<LicenseIssuerKey> keys,
  ) {
    final result = <String, LicenseIssuerKey>{};
    for (final key in keys) {
      if (result.containsKey(key.keyId)) {
        throw ArgumentError('Duplicate issuer key id: ${key.keyId}');
      }
      result[key.keyId] = key;
    }
    return Map<String, LicenseIssuerKey>.unmodifiable(result);
  }
}

enum LicenseVerificationStatus {
  valid,
  validWithUnsupportedFeatures,
  validWithoutGrantedFeatures,
  invalidFormat,
  invalidPayload,
  unsupportedSchema,
  unknownIssuer,
  issuerCompromised,
  invalidIssuerKey,
  invalidSignature,
  revoked,
  wrongProduct,
  unsupportedRevision,
  wrongApplication,
  wrongDevice,
}

class LicenseVerificationResult {
  const LicenseVerificationResult(this.status, [this.payload]);

  final LicenseVerificationStatus status;
  final LicensePayload? payload;

  /// True when signature, issuer, payload, protocol, product, application and
  /// device binding are valid, even when the Token grants no AI access.
  bool get isAuthenticated =>
      status == LicenseVerificationStatus.valid ||
      status == LicenseVerificationStatus.validWithUnsupportedFeatures ||
      status == LicenseVerificationStatus.validWithoutGrantedFeatures;

  /// True only when the authenticated Token grants the current AI entitlement.
  bool get isValid =>
      status == LicenseVerificationStatus.valid ||
      status == LicenseVerificationStatus.validWithUnsupportedFeatures;
}

class LicenseVerifier {
  LicenseVerifier({
    required LicenseKeyRing keyRing,
    Set<String> revokedLicenseIds = const {},
    Ed25519? algorithm,
  })  : _keyRing = keyRing,
        _revokedLicenseIds = Set.unmodifiable(revokedLicenseIds),
        _algorithm = algorithm ?? Ed25519();

  final LicenseKeyRing _keyRing;
  final Set<String> _revokedLicenseIds;
  final Ed25519 _algorithm;

  Future<LicenseVerificationResult> verify(
    String token, {
    required String expectedDevicePublicKeySha256,
    String expectedAppId = yanjiLicenseAppId,
  }) async {
    if (token.length > _maxLicenseTokenLength) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidFormat,
      );
    }

    final normalizedToken = token.trim();
    final parts = normalizedToken.split('.');
    if (parts.length != 3 ||
        parts[0] != _licenseTokenPrefix ||
        !_isBase64UrlSegment(parts[1]) ||
        !_isBase64UrlSegment(parts[2])) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidFormat,
      );
    }

    late final List<int> payloadBytes;
    late final List<int> signatureBytes;
    try {
      payloadBytes = _decodeBase64Url(parts[1]);
      signatureBytes = _decodeBase64Url(parts[2]);
    } on FormatException {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidFormat,
      );
    }
    if (payloadBytes.isEmpty ||
        payloadBytes.length > _maxLicensePayloadLength ||
        signatureBytes.length != 64) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidFormat,
      );
    }

    late final Object? decodedPayload;
    late final Map<String, Object?> untrustedJson;
    late final List<int> canonicalPayloadBytes;
    try {
      decodedPayload = jsonDecode(utf8.decode(payloadBytes));
      if (decodedPayload is! Map) {
        return const LicenseVerificationResult(
          LicenseVerificationStatus.invalidPayload,
        );
      }
      untrustedJson = Map<String, Object?>.from(decodedPayload);
      canonicalPayloadBytes = canonicalJsonBytes(decodedPayload);
    } on FormatException {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    } on TypeError {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    } on ArgumentError {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    }

    // Protocol revision 1 carries exactly one canonical JSON byte sequence.
    // Reject equivalent-but-noncanonical JSON instead of accepting multiple
    // textual encodings for the same signed payload.
    if (!_bytesEqual(payloadBytes, canonicalPayloadBytes)) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    }

    final issuerKeyId = untrustedJson['issuer_key_id'];
    if (issuerKeyId is! String || issuerKeyId.isEmpty) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    }
    final issuerKey = _keyRing[issuerKeyId];
    if (issuerKey == null) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.unknownIssuer,
      );
    }
    if (!issuerKey.mayVerify) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.issuerCompromised,
      );
    }
    if (issuerKey.publicKey.length != 32) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidIssuerKey,
      );
    }

    final signedMessage = <int>[
      ...utf8.encode(_licenseSignatureDomain),
      ...canonicalPayloadBytes,
    ];
    final signature = Signature(
      signatureBytes,
      publicKey: SimplePublicKey(
        issuerKey.publicKey,
        type: KeyPairType.ed25519,
      ),
    );

    late final bool signatureIsValid;
    try {
      signatureIsValid = await _algorithm.verify(
        signedMessage,
        signature: signature,
      );
    } on Object {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidSignature,
      );
    }
    if (!signatureIsValid) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidSignature,
      );
    }

    final schemaVersion = untrustedJson['schema_version'];
    if (schemaVersion is! int) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    }
    if (schemaVersion != 1) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.unsupportedSchema,
      );
    }

    late final LicensePayload payload;
    try {
      payload = LicensePayload.fromJson(untrustedJson);
    } on FormatException {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    }

    if (payload.productId != ProfessionalEditionCatalog.productId ||
        !payload.perpetual) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.wrongProduct,
      );
    }
    if (payload.protocolRevision <
            ProfessionalEditionCatalog.minimumSupportedProtocolRevision ||
        !ProfessionalEditionCatalog.supportedProtocolRevisions
            .contains(payload.protocolRevision)) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.unsupportedRevision,
      );
    }
    if (payload.appId != expectedAppId) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.wrongApplication,
      );
    }
    if (payload.devicePublicKeySha256 != expectedDevicePublicKeySha256) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.wrongDevice,
      );
    }
    if (_revokedLicenseIds.contains(payload.licenseId)) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.revoked,
      );
    }

    if (payload.grantedFeatureIds.isEmpty) {
      return LicenseVerificationResult(
        LicenseVerificationStatus.validWithoutGrantedFeatures,
        payload,
      );
    }
    if (payload.unsupportedFeatureIds.isNotEmpty) {
      return LicenseVerificationResult(
        LicenseVerificationStatus.validWithUnsupportedFeatures,
        payload,
      );
    }
    return LicenseVerificationResult(
      LicenseVerificationStatus.valid,
      payload,
    );
  }

  static List<int> canonicalJsonBytes(Object? value) =>
      utf8.encode(_canonicalJson(value));

  static String _canonicalJson(Object? value) {
    if (value == null || value is bool || value is String) {
      return jsonEncode(value);
    }
    if (value is int) return value.toString();
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('JCS does not support non-finite numbers.');
      }
      // License v1 has no floating-point fields. Reject rather than introduce
      // an implementation-specific number serializer into the signed schema.
      throw const FormatException('Floating-point values are not allowed in license v1.');
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    if (value is Map) {
      final map = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('JCS object keys must be strings.');
        }
        map[entry.key as String] = entry.value;
      }
      final keys = map.keys.toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(map[key])}').join(',')}}';
    }
    throw FormatException('Unsupported JCS value: ${value.runtimeType}');
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static String fingerprintDevicePublicKey(List<int> subjectPublicKeyInfoDer) {
    final digest = crypto.sha256.convert(subjectPublicKeyInfoDer).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  static bool _isBase64UrlSegment(String value) =>
      value.isNotEmpty &&
      value.length % 4 != 1 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

  static List<int> _decodeBase64Url(String value) {
    final normalized = value.padRight(
      value.length + ((4 - value.length % 4) % 4),
      '=',
    );
    return base64Url.decode(normalized);
  }
}
