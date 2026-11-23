import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'license_model.dart';

const _licenseTokenPrefix = 'YANJI1';
const _maxLicenseTokenLength = 16384;
const _maxLicensePayloadLength = 12288;

enum LicenseVerificationStatus {
  valid,
  invalidFormat,
  invalidPayload,
  unknownIssuer,
  invalidIssuerKey,
  invalidSignature,
  wrongProduct,
  wrongApplication,
  wrongDevice,
}

class LicenseVerificationResult {
  const LicenseVerificationResult(this.status, [this.payload]);

  final LicenseVerificationStatus status;
  final LicensePayload? payload;

  bool get isValid => status == LicenseVerificationStatus.valid;
}

class LicenseVerifier {
  LicenseVerifier({
    required Map<String, List<int>> trustedIssuerPublicKeys,
    Ed25519? algorithm,
  })  : _trustedIssuerPublicKeys = Map.unmodifiable({
          for (final entry in trustedIssuerPublicKeys.entries)
            entry.key: List<int>.unmodifiable(entry.value),
        }),
        _algorithm = algorithm ?? Ed25519();

  final Map<String, List<int>> _trustedIssuerPublicKeys;
  final Ed25519 _algorithm;

  /// Verifies the exact ASCII bytes "YANJI1." + the original payload segment.
  /// JSON is parsed only after signature verification and is never re-serialized.
  Future<LicenseVerificationResult> verify(
    String token, {
    required String expectedDeviceKeySha256,
    String expectedAppId = yanjiLicenseAppId,
  }) async {
    if (token.length > _maxLicenseTokenLength) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidFormat,
      );
    }

    final parts = token.trim().split('.');
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

    late final Map<String, Object?> untrustedJson;
    try {
      final decoded = jsonDecode(utf8.decode(payloadBytes));
      if (decoded is! Map) {
        return const LicenseVerificationResult(
          LicenseVerificationStatus.invalidPayload,
        );
      }
      untrustedJson = Map<String, Object?>.from(decoded);
    } on FormatException {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    } on TypeError {
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
    final issuerPublicKey = _trustedIssuerPublicKeys[issuerKeyId];
    if (issuerPublicKey == null) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.unknownIssuer,
      );
    }
    if (issuerPublicKey.length != 32) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidIssuerKey,
      );
    }

    final signedMessage = utf8.encode(_licenseTokenPrefix + '.' + parts[1]);
    final signature = Signature(
      signatureBytes,
      publicKey: SimplePublicKey(
        issuerPublicKey,
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

    late final LicensePayload payload;
    try {
      payload = LicensePayload.fromJson(untrustedJson);
    } on FormatException {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.invalidPayload,
      );
    }

    if (payload.productId != yanjiLifetimeProductId ||
        payload.productRevision < 1 ||
        !payload.perpetual) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.wrongProduct,
      );
    }
    if (payload.appId != expectedAppId) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.wrongApplication,
      );
    }
    if (payload.deviceKeySha256 != expectedDeviceKeySha256) {
      return const LicenseVerificationResult(
        LicenseVerificationStatus.wrongDevice,
      );
    }

    return LicenseVerificationResult(
      LicenseVerificationStatus.valid,
      payload,
    );
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
