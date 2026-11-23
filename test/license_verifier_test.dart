import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_model.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';

void main() {
  const issuerKeyId = 'issuer-test-01';
  final algorithm = Ed25519();

  Future<Map<String, Object>> signedFixture({
    String productId = 'yanji_pro_lifetime',
    int productRevision = 1,
    String appId = 'com.nihaisha.nihaisha_app',
    String deviceKeySha256 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    List<String> features = const [
      'ai_advanced',
      'contextual_assistant',
      'advanced_learning',
      'advanced_export',
    ],
  }) async {
    final keyPair = await algorithm.newKeyPair();
    final payload = <String, Object>{
      'schema_version': 1,
      'license_id': 'LIC-00000001',
      'order_id': 'YJ-20261123-0001',
      'product_id': productId,
      'product_revision': productRevision,
      'app_id': appId,
      'perpetual': true,
      'features': features,
      'device_key_sha256': deviceKeySha256,
      'issued_at': '2026-11-23T09:00:00Z',
      'issuer_key_id': issuerKeyId,
    };
    final payloadSegment = base64UrlEncode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    final signedMessage = utf8.encode('YANJI1.' + payloadSegment);
    final signature = await algorithm.sign(signedMessage, keyPair: keyPair);
    final publicKey = signature.publicKey;
    if (publicKey is! SimplePublicKey) {
      throw StateError('Ed25519 returned a non-simple public key.');
    }
    final token = 'YANJI1.' +
        payloadSegment +
        '.' +
        base64UrlEncode(signature.bytes).replaceAll('=', '');
    return {
      'token': token,
      'public_key': publicKey.bytes,
    };
  }

  test('accepts a valid perpetual license bound to this device', () async {
    final fixture = await signedFixture();
    final verifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: fixture['public_key'] as List<int>,
      },
    );

    final result = await verifier.verify(
      fixture['token'] as String,
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );

    expect(result.status, LicenseVerificationStatus.valid);
    expect(result.isValid, isTrue);
    expect(result.payload?.perpetual, isTrue);
    expect(result.payload?.grants(LicenseFeature.contextualAssistant), isTrue);
  });

  test('rejects tampering with the signed feature list', () async {
    final fixture = await signedFixture();
    final parts = (fixture['token'] as String).split('.');
    final payload = utf8.decode(
      base64Url.decode(
        parts[1].padRight(
          parts[1].length + ((4 - parts[1].length % 4) % 4),
          '=',
        ),
      ),
    );
    final changedPayload = payload.replaceFirst('ai_advanced', 'xx_advanced');
    final changedSegment = base64UrlEncode(utf8.encode(changedPayload))
        .replaceAll('=', '');
    final tampered = 'YANJI1.' + changedSegment + '.' + parts[2];

    final verifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: fixture['public_key'] as List<int>,
      },
    );
    final result = await verifier.verify(
      tampered,
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );

    expect(result.status, LicenseVerificationStatus.invalidSignature);
  });

  test('rejects a valid signature for another device', () async {
    final fixture = await signedFixture();
    final verifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: fixture['public_key'] as List<int>,
      },
    );
    final result = await verifier.verify(
      fixture['token'] as String,
      expectedDeviceKeySha256:
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    );
    expect(result.status, LicenseVerificationStatus.wrongDevice);
  });

  test('rejects a valid signature for another application id', () async {
    final fixture = await signedFixture(appId: 'com.example.other');
    final verifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: fixture['public_key'] as List<int>,
      },
    );
    final result = await verifier.verify(
      fixture['token'] as String,
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    expect(result.status, LicenseVerificationStatus.wrongApplication);
  });

  test('rejects an unknown issuer key id', () async {
    final fixture = await signedFixture();
    final verifier = LicenseVerifier(trustedIssuerPublicKeys: const {});
    final result = await verifier.verify(
      fixture['token'] as String,
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    expect(result.status, LicenseVerificationStatus.unknownIssuer);
  });

  test('rejects malformed token and unsupported product', () async {
    final malformedVerifier = LicenseVerifier(
      trustedIssuerPublicKeys: const {},
    );
    final malformed = await malformedVerifier.verify(
      'YANJI1.not-valid.signature',
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );

    final otherProductFixture = await signedFixture(productId: 'other_product');
    final otherProductVerifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: otherProductFixture['public_key'] as List<int>,
      },
    );
    final otherProduct = await otherProductVerifier.verify(
      otherProductFixture['token'] as String,
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );

    expect(malformed.status, LicenseVerificationStatus.invalidFormat);
    expect(otherProduct.status, LicenseVerificationStatus.wrongProduct);
  });

  test('rejects an unsupported product revision', () async {
    final fixture = await signedFixture(productRevision: 2);
    final verifier = LicenseVerifier(
      trustedIssuerPublicKeys: {
        issuerKeyId: fixture['public_key'] as List<int>,
      },
    );
    final result = await verifier.verify(
      fixture['token'] as String,
      expectedDeviceKeySha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    expect(result.status, LicenseVerificationStatus.wrongProduct);
  });

  test('computes a Base64URL SHA-256 fingerprint', () {
    final fingerprint = LicenseVerifier.fingerprintDevicePublicKey(
      List<int>.generate(32, (index) => index),
    );
    expect(fingerprint.length, 43);
    expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fingerprint), isTrue);
  });
}
