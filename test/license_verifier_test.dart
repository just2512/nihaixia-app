import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_model.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';

Future<Map<String, dynamic>> _loadVectors() async {
  final file = File('test/fixtures/pro-license-test-vectors.json');
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

String _encodeSegment(List<int> value) =>
    base64UrlEncode(value).replaceAll('=', '');

List<int> _decodeSegment(String value) => base64Url.decode(
      value.padRight(value.length + ((4 - value.length % 4) % 4), '='),
    );

Future<String> _signToken(
  Map<String, dynamic> payload,
  KeyPair keyPair,
) async {
  final algorithm = Ed25519();
  final segment = _encodeSegment(utf8.encode(jsonEncode(payload)));
  final message = utf8.encode('YANJI1.' + segment);
  final signature = await algorithm.sign(message, keyPair: keyPair);
  return 'YANJI1.' + segment + '.' + _encodeSegment(signature.bytes);
}

void main() {
  late Map<String, dynamic> vectors;
  late Map<String, dynamic> licenseFixture;
  late LicenseVerifier verifier;
  late String issuerKeyId;
  late String deviceFingerprint;
  late String requestId;
  late String requestNonce;
  late String requestSha256;

  setUpAll(() async {
    vectors = await _loadVectors();
    final deviceRequest = vectors['device_request'] as Map<String, dynamic>;
    licenseFixture = vectors['valid_license'] as Map<String, dynamic>;
    issuerKeyId = vectors['issuer_key_id'] as String;
    deviceFingerprint = deviceRequest['device_key_sha256'] as String;
    final requestPayload =
        deviceRequest['request_payload'] as Map<String, dynamic>;
    requestId = requestPayload['request_id'] as String;
    requestNonce = requestPayload['request_nonce'] as String;
    requestSha256 = deviceRequest['request_sha256'] as String;

    verifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: _decodeSegment(
          vectors['issuer_public_key_raw_base64url'] as String,
        ),
      },
    );
  });

  test('accepts shared Python/Dart protocol vector', () async {
    final result = await verifier.verify(
      licenseFixture['token'] as String,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(result.status, LicenseVerificationStatus.valid);
    expect(result.isValid, isTrue);
    expect(result.payload?.licenseId, 'LIC-TEST-VECTOR-0001');
    expect(result.payload?.requestId, requestId);
    expect(result.payload?.requestNonce, requestNonce);
    expect(result.payload?.requestSha256, requestSha256);
    expect(result.payload?.deviceKeySecurityLevel, 'TRUSTED_ENVIRONMENT');
    expect(
      result.payload?.grants(LicenseFeature.contextualAssistant),
      isTrue,
    );
  });

  test('rejects feature and app id payload tampering', () async {
    final parts = (licenseFixture['token'] as String).split('.');
    final original = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(_decodeSegment(parts[1]))) as Map,
    );
    final mutatedPayloads = <Map<String, dynamic>>[
      {...original, 'app_id': 'com.example.other'},
      {
        ...original,
        'features': [
          'ai_advanced',
          'contextual_assistant',
          'advanced_learning',
          'altered_feature',
        ],
      },
    ];

    for (final payload in mutatedPayloads) {
      final changedSegment =
          _encodeSegment(utf8.encode(jsonEncode(payload)));
      final tampered = 'YANJI1.' + changedSegment + '.' + parts[2];
      final result = await verifier.verify(
        tampered,
        expectedDeviceKeySha256: deviceFingerprint,
        expectedRequestId: requestId,
        expectedRequestNonce: requestNonce,
        expectedRequestSha256: requestSha256,
      );
      expect(result.status, LicenseVerificationStatus.invalidSignature);
    }
  });

  test('rejects a one-bit signature mutation', () async {
    final parts = (licenseFixture['token'] as String).split('.');
    final signature = _decodeSegment(parts[2]);
    signature[signature.length - 1] ^= 0x01;
    final tampered =
        'YANJI1.' + parts[1] + '.' + _encodeSegment(signature);
    final result = await verifier.verify(
      tampered,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(result.status, LicenseVerificationStatus.invalidSignature);
  });

  test('rejects the same license on another device', () async {
    final result = await verifier.verify(
      licenseFixture['token'] as String,
      expectedDeviceKeySha256: List<String>.filled(43, 'B').join(),
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(result.status, LicenseVerificationStatus.wrongDevice);
  });

  test('rejects a license returned for another request', () async {
    final result = await verifier.verify(
      licenseFixture['token'] as String,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: List<String>.filled(43, 'A').join(),
    );

    expect(result.status, LicenseVerificationStatus.requestMismatch);
  });

  test('rejects a different app id and revoked license id', () async {
    final wrongApp = await verifier.verify(
      licenseFixture['token'] as String,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
      expectedAppId: 'com.example.other',
    );
    final revokedVerifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: _decodeSegment(
          vectors['issuer_public_key_raw_base64url'] as String,
        ),
      },
      revokedLicenseIds: const {'LIC-TEST-VECTOR-0001'},
    );
    final revoked = await revokedVerifier.verify(
      licenseFixture['token'] as String,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(wrongApp.status, LicenseVerificationStatus.wrongApplication);
    expect(revoked.status, LicenseVerificationStatus.revoked);
  });

  test('unknown feature identifiers are ignored, never granted', () async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    if (publicKey is! SimplePublicKey) {
      throw StateError('Expected an Ed25519 simple public key.');
    }
    final basePayload = Map<String, dynamic>.from(
      licenseFixture['payload'] as Map,
    );
    final payload = {
      ...basePayload,
      'license_id': 'LIC-TEST-UNKNOWN-ONLY',
      'features': ['future_feature_2027'],
    };
    final token = await _signToken(payload, keyPair);
    final dynamicVerifier = LicenseVerifier(
      trustedIssuerPublicKeys: {'dynamic-test-key': publicKey.bytes},
    );
    final result = await dynamicVerifier.verify(
      token,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(result.status, LicenseVerificationStatus.unknownFeatureOnly);
    expect(result.isValid, isFalse);
    expect(result.payload?.unknownFeatureIds, {'future_feature_2027'});
    expect(result.payload?.grants(LicenseFeature.aiAdvanced), isFalse);
  });

  test('known feature plus unknown feature grants only the known feature',
      () async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    if (publicKey is! SimplePublicKey) {
      throw StateError('Expected an Ed25519 simple public key.');
    }
    final basePayload = Map<String, dynamic>.from(
      licenseFixture['payload'] as Map,
    );
    final payload = {
      ...basePayload,
      'license_id': 'LIC-TEST-KNOWN-AND-UNKNOWN',
      'features': ['ai_advanced', 'future_feature_2027'],
    };
    final token = await _signToken(payload, keyPair);
    final dynamicVerifier = LicenseVerifier(
      trustedIssuerPublicKeys: {'dynamic-test-key': publicKey.bytes},
    );
    final result = await dynamicVerifier.verify(
      token,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(result.status, LicenseVerificationStatus.validWithUnknownFeatures);
    expect(result.isValid, isTrue);
    expect(result.payload?.grants(LicenseFeature.aiAdvanced), isTrue);
    expect(result.payload?.grants(LicenseFeature.advancedExport), isFalse);
  });

  test('rejects unsupported product revisions after signature verification',
      () async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    if (publicKey is! SimplePublicKey) {
      throw StateError('Expected an Ed25519 simple public key.');
    }
    final basePayload = Map<String, dynamic>.from(
      licenseFixture['payload'] as Map,
    );
    final payload = {
      ...basePayload,
      'license_id': 'LIC-TEST-REVISION-2',
      'product_revision': 2,
    };
    final token = await _signToken(payload, keyPair);
    final dynamicVerifier = LicenseVerifier(
      trustedIssuerPublicKeys: {'dynamic-test-key': publicKey.bytes},
    );
    final result = await dynamicVerifier.verify(
      token,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(
      result.status,
      LicenseVerificationStatus.unsupportedProductRevision,
    );
  });

  test('rejects unknown and compromised issuer keys', () async {
    final token = licenseFixture['token'] as String;
    final noKeys = LicenseVerifier(trustedIssuerPublicKeys: const {});
    final unknown = await noKeys.verify(
      token,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );
    final compromised = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: _decodeSegment(
          vectors['issuer_public_key_raw_base64url'] as String,
        ),
      },
      compromisedIssuerKeyIds: {issuerKeyId},
    );
    final rejected = await compromised.verify(
      token,
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(unknown.status, LicenseVerificationStatus.unknownIssuer);
    expect(rejected.status, LicenseVerificationStatus.issuerCompromised);
  });

  test('rejects malformed and oversized tokens', () async {
    final malformed = await verifier.verify(
      'YANJI1.not-valid.signature',
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );
    final oversized = await verifier.verify(
      List<String>.filled(16385, 'X').join(),
      expectedDeviceKeySha256: deviceFingerprint,
      expectedRequestId: requestId,
      expectedRequestNonce: requestNonce,
      expectedRequestSha256: requestSha256,
    );

    expect(malformed.status, LicenseVerificationStatus.invalidFormat);
    expect(oversized.status, LicenseVerificationStatus.invalidFormat);
  });

  test('computes a Base64URL SHA-256 fingerprint', () {
    final fingerprint = LicenseVerifier.fingerprintDevicePublicKey(
      List<int>.generate(32, (index) => index),
    );
    expect(fingerprint.length, 43);
    expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fingerprint), isTrue);
  });
}
