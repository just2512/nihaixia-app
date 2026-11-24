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
  final canonicalPayload = LicenseVerifier.canonicalJsonBytes(payload);
  final message = <int>[
    ...utf8.encode('YANJI-PRO-LICENSE-V1\u0000'),
    ...canonicalPayload,
  ];
  final signature = await Ed25519().sign(message, keyPair: keyPair);
  return 'YANJI1.${_encodeSegment(canonicalPayload)}.'
      '${_encodeSegment(signature.bytes)}';
}

LicenseKeyRing _keyRing(
  String keyId,
  List<int> publicKey, {
  LicenseIssuerKeyStatus status = LicenseIssuerKeyStatus.active,
}) =>
    LicenseKeyRing(
      keys: [
        LicenseIssuerKey(
          keyId: keyId,
          publicKey: publicKey,
          status: status,
        ),
      ],
    );

void main() {
  late Map<String, dynamic> vectors;
  late Map<String, dynamic> licenseFixture;
  late LicenseVerifier verifier;
  late String issuerKeyId;
  late String deviceFingerprint;

  setUpAll(() async {
    vectors = await _loadVectors();
    final deviceRequest = vectors['device_request'] as Map<String, dynamic>;
    licenseFixture = vectors['valid_license'] as Map<String, dynamic>;
    issuerKeyId = vectors['issuer_key_id'] as String;
    deviceFingerprint = deviceRequest['device_key_sha256'] as String;

    verifier = LicenseVerifier(
      keyRing: _keyRing(
        issuerKeyId,
        _decodeSegment(
          vectors['issuer_public_key_raw_base64url'] as String,
        ),
      ),
    );
  });

  Future<LicenseVerificationResult> verifyDynamicPayload(
    Map<String, dynamic> payload,
    KeyPair keyPair,
  ) async {
    final publicKey = await keyPair.extractPublicKey() as SimplePublicKey;
    final token = await _signToken(payload, keyPair);
    final dynamicVerifier = LicenseVerifier(
      keyRing: _keyRing('dynamic-test-key', publicKey.bytes),
    );
    return dynamicVerifier.verify(
      token,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );
  }

  Map<String, dynamic> basePayload() =>
      Map<String, dynamic>.from(licenseFixture['payload'] as Map);

  test('accepts the historical revision-1 Python/Dart JCS vector and maps it to ai_access', () async {
    final token = licenseFixture['token'] as String;
    final parts = token.split('.');
    final payloadBytes = _decodeSegment(parts[1]);
    final canonicalPayload = LicenseVerifier.canonicalJsonBytes(
      licenseFixture['payload'],
    );

    expect(payloadBytes, canonicalPayload);

    final result = await verifier.verify(
      token,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );

    expect(result.status, LicenseVerificationStatus.valid);
    expect(result.isValid, isTrue);
    expect(result.payload?.licenseId, 'LIC-TEST-VECTOR-0001');
    expect(result.payload?.protocolRevision, 1);
    expect(
      result.payload?.grantedFeatureIds,
      {'ai_access'},
    );
    expect(result.payload?.requestId,
        '8de4e5a0-9db7-4d1d-8a36-610c393f1c22');
    expect(result.payload?.grantsAiAccess, isTrue);
    expect(result.payload?.grants(LicenseFeature.aiAccess), isTrue);
    expect(result.payload?.grants(LicenseFeature.aiAdvanced), isFalse);
    expect(result.payload?.grants(LicenseFeature.contextualAssistant), isFalse);
    expect(result.payload?.grants(LicenseFeature.advancedLearning), isFalse);
  });

  test('rejects noncanonical JSON even when it decodes to the same object', () async {
    final parts = (licenseFixture['token'] as String).split('.');
    final payload = basePayload();
    final reversed = Map<String, dynamic>.fromEntries(
      payload.entries.toList().reversed,
    );
    final noncanonical = _encodeSegment(utf8.encode(jsonEncode(reversed)));
    final token = 'YANJI1.$noncanonical.${parts[2]}';

    final result = await verifier.verify(
      token,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );

    expect(result.status, LicenseVerificationStatus.invalidPayload);
  });

  test('rejects payload tampering and one-bit signature mutation', () async {
    final parts = (licenseFixture['token'] as String).split('.');
    final tamperedPayload = basePayload()..['app_id'] = 'com.example.other';
    final changedBytes = LicenseVerifier.canonicalJsonBytes(tamperedPayload);
    final tampered = 'YANJI1.${_encodeSegment(changedBytes)}.${parts[2]}';
    final tamperedResult = await verifier.verify(
      tampered,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );

    final signature = _decodeSegment(parts[2]);
    signature[signature.length - 1] ^= 0x01;
    final signatureTampered =
        'YANJI1.${parts[1]}.${_encodeSegment(signature)}';
    final signatureResult = await verifier.verify(
      signatureTampered,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );

    expect(tamperedResult.status, LicenseVerificationStatus.invalidSignature);
    expect(signatureResult.status,
        LicenseVerificationStatus.invalidSignature);
  });

  test('rejects a token bound to another device', () async {
    final result = await verifier.verify(
      licenseFixture['token'] as String,
      expectedDevicePublicKeySha256: List<String>.filled(43, 'B').join(),
    );
    expect(result.status, LicenseVerificationStatus.wrongDevice);
  });

  test('rejects a different application and a locally revoked license', () async {
    final wrongApp = await verifier.verify(
      licenseFixture['token'] as String,
      expectedDevicePublicKeySha256: deviceFingerprint,
      expectedAppId: 'com.example.other',
    );
    final revokedVerifier = LicenseVerifier(
      keyRing: _keyRing(
        issuerKeyId,
        _decodeSegment(
          vectors['issuer_public_key_raw_base64url'] as String,
        ),
      ),
      revokedLicenseIds: const {'LIC-TEST-VECTOR-0001'},
    );
    final revoked = await revokedVerifier.verify(
      licenseFixture['token'] as String,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );

    expect(wrongApp.status, LicenseVerificationStatus.wrongApplication);
    expect(revoked.status, LicenseVerificationStatus.revoked);
  });

  test('unknown Feature claims are diagnostic and never granted', () async {
    final keyPair = await Ed25519().newKeyPair();
    final payload = {
      ...basePayload(),
      'issuer_key_id': 'dynamic-test-key',
      'license_id': 'LIC-TEST-KNOWN-AND-UNKNOWN',
      'features': ['ai_advanced', 'future_feature_2027'],
    };
    final result = await verifyDynamicPayload(payload, keyPair);

    expect(result.status,
        LicenseVerificationStatus.validWithUnsupportedFeatures);
    expect(result.isValid, isTrue);
    expect(result.payload?.grantedFeatureIds, {'ai_access'});
    expect(result.payload?.unknownFeatureIds, {'future_feature_2027'});
    expect(result.payload?.grantsAiAccess, isTrue);
  });

  test('known but reserved Feature is not granted and does not invalidate other claims', () async {
    final keyPair = await Ed25519().newKeyPair();
    final mixed = {
      ...basePayload(),
      'issuer_key_id': 'dynamic-test-key',
      'license_id': 'LIC-TEST-RESERVED-MIXED',
      'features': ['advanced_learning', 'ai_advanced'],
    };
    final mixedResult = await verifyDynamicPayload(mixed, keyPair);

    final reservedOnlyKeyPair = await Ed25519().newKeyPair();
    final reservedOnly = {
      ...basePayload(),
      'issuer_key_id': 'dynamic-test-key',
      'license_id': 'LIC-TEST-RESERVED-ONLY',
      'features': ['advanced_export'],
    };
    final reservedOnlyResult =
        await verifyDynamicPayload(reservedOnly, reservedOnlyKeyPair);

    expect(mixedResult.status,
        LicenseVerificationStatus.validWithUnsupportedFeatures);
    expect(mixedResult.payload?.grantedFeatureIds, {'ai_access'});
    expect(mixedResult.payload?.knownButNotAllowedFeatureIds,
        {'advanced_learning'});
    expect(reservedOnlyResult.status,
        LicenseVerificationStatus.validWithoutGrantedFeatures);
    expect(reservedOnlyResult.isValid, isFalse);
    expect(reservedOnlyResult.payload?.grantedFeatureIds, isEmpty);
  });

  test('accepts protocol revision 2 only through the single ai_access claim', () async {
    final keyPair = await Ed25519().newKeyPair();
    final payload = {
      ...basePayload(),
      'issuer_key_id': 'dynamic-test-key',
      'license_id': 'LIC-TEST-REVISION-2-AI-ACCESS',
      'protocol_revision': 2,
      'features': ['ai_access'],
    };
    final result = await verifyDynamicPayload(payload, keyPair);

    expect(result.status, LicenseVerificationStatus.valid);
    expect(result.isValid, isTrue);
    expect(result.payload?.grantsAiAccess, isTrue);
    expect(result.payload?.grantedFeatureIds, {'ai_access'});
  });

  test('revision 2 does not reinterpret legacy revision-1 claims', () async {
    final keyPair = await Ed25519().newKeyPair();
    final payload = {
      ...basePayload(),
      'issuer_key_id': 'dynamic-test-key',
      'license_id': 'LIC-TEST-REVISION-2-LEGACY-CLAIMS',
      'protocol_revision': 2,
      'features': ['ai_advanced'],
    };
    final result = await verifyDynamicPayload(payload, keyPair);

    expect(result.status, LicenseVerificationStatus.validWithoutGrantedFeatures);
    expect(result.isValid, isFalse);
    expect(result.payload?.grantsAiAccess, isFalse);
    expect(result.payload?.knownButNotAllowedFeatureIds, {'ai_advanced'});
  });

  test('revision 1 maps either historical AI claim to the same ai_access entitlement', () async {
    final keyPair = await Ed25519().newKeyPair();
    for (final legacyFeature in ['ai_advanced', 'contextual_assistant']) {
      final payload = {
        ...basePayload(),
        'issuer_key_id': 'dynamic-test-key',
        'license_id': 'LIC-TEST-LEGACY-$legacyFeature',
        'protocol_revision': 1,
        'features': [legacyFeature],
      };
      final result = await verifyDynamicPayload(payload, keyPair);

      expect(result.status, LicenseVerificationStatus.valid);
      expect(result.payload?.grantsAiAccess, isTrue);
      expect(result.payload?.grantedFeatureIds, {'ai_access'});
    }
  });

  test('rejects unsupported protocol revisions after signature verification', () async {
    final keyPair = await Ed25519().newKeyPair();
    final payload = {
      ...basePayload(),
      'issuer_key_id': 'dynamic-test-key',
      'license_id': 'LIC-TEST-REVISION-3',
      'protocol_revision': 3,
      'features': ['ai_access'],
    };
    final result = await verifyDynamicPayload(payload, keyPair);

    expect(result.status, LicenseVerificationStatus.unsupportedRevision);
  });

  test('issuer Key Ring accepts active, standby and retired keys', () async {
    final token = licenseFixture['token'] as String;
    final publicKey = _decodeSegment(
      vectors['issuer_public_key_raw_base64url'] as String,
    );
    for (final status in [
      LicenseIssuerKeyStatus.active,
      LicenseIssuerKeyStatus.standby,
      LicenseIssuerKeyStatus.retired,
    ]) {
      final keyRing = _keyRing(issuerKeyId, publicKey, status: status);
      final result = await LicenseVerifier(keyRing: keyRing).verify(
        token,
        expectedDevicePublicKeySha256: deviceFingerprint,
      );
      expect(result.status, LicenseVerificationStatus.valid, reason: '$status');
    }

    for (final status in [
      LicenseIssuerKeyStatus.revoked,
      LicenseIssuerKeyStatus.compromised,
    ]) {
      final result = await LicenseVerifier(
        keyRing: _keyRing(issuerKeyId, publicKey, status: status),
      ).verify(
        token,
        expectedDevicePublicKeySha256: deviceFingerprint,
      );
      expect(result.status, LicenseVerificationStatus.issuerCompromised);
    }
  });

  test('rejects unknown issuer, malformed and oversized tokens', () async {
    final token = licenseFixture['token'] as String;
    final unknownIssuer = await LicenseVerifier(
      keyRing: LicenseKeyRing(keys: const []),
    ).verify(
      token,
      expectedDevicePublicKeySha256: deviceFingerprint,
    );
    final malformed = await verifier.verify(
      'YANJI1.not-valid.signature',
      expectedDevicePublicKeySha256: deviceFingerprint,
    );
    final oversized = await verifier.verify(
      List<String>.filled(16385, 'X').join(),
      expectedDevicePublicKeySha256: deviceFingerprint,
    );

    expect(unknownIssuer.status, LicenseVerificationStatus.unknownIssuer);
    expect(malformed.status, LicenseVerificationStatus.invalidFormat);
    expect(oversized.status, LicenseVerificationStatus.invalidFormat);
  });

  test('computes a Base64URL SHA-256 public-key fingerprint', () {
    final fingerprint = LicenseVerifier.fingerprintDevicePublicKey(
      List<int>.generate(32, (index) => index),
    );
    expect(fingerprint.length, 43);
    expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fingerprint), isTrue);
  });
}
