import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/license_activation_request_builder.dart';

class _FakeLicensePlatform implements LicensePlatform {
  _FakeLicensePlatform({
    required this.key,
    this.missingKey = false,
  });

  final DeviceKeyInfo key;
  final bool missingKey;
  int getKeyCalls = 0;
  int createKeyCalls = 0;
  int signCalls = 0;
  String? signedPayload;

  @override
  Future<String?> readActiveToken() async => null;

  @override
  Future<void> writeActiveTokenAtomically(String token) async {}

  @override
  Future<void> deleteActiveToken() async {}

  @override
  Future<DeviceKeyInfo> getDeviceKey() async {
    getKeyCalls++;
    if (missingKey && createKeyCalls == 0) {
      throw const LicensePlatformFailure('keyMissing');
    }
    return key;
  }

  @override
  Future<DeviceKeyInfo> createDeviceKeyForActivation() async {
    createKeyCalls++;
    return key;
  }

  @override
  Future<String> signActivationRequest(String payloadBase64Url) async {
    signCalls++;
    signedPayload = payloadBase64Url;
    return 'MEUCIQDsignature';
  }

  @override
  Future<DeviceKeyInfo> checkPrivateKeyUsability() async => key;
}

DeviceKeyInfo _key() {
  final keyBytes = List<int>.generate(32, (index) => index + 1);
  return DeviceKeyInfo(
    spkiDerBase64Url: base64UrlEncode([0x30, 0x01, 0x00]).replaceAll('=', ''),
    sha256Base64Url: base64UrlEncode(keyBytes).replaceAll('=', ''),
    securityLevel: 'TRUSTED_ENVIRONMENT',
    strongBoxFallback: true,
  );
}

void main() {
  group('LicenseActivationRequestBuilder', () {
    test('reuses an existing key without creating or replacing it', () async {
      final platform = _FakeLicensePlatform(key: _key());

      final result = await LicenseActivationRequestBuilder.create(
        platform: platform,
        clock: () => DateTime.utc(2026, 11, 24, 9, 30),
        random: Random(42),
      );

      expect(platform.getKeyCalls, 1);
      expect(platform.createKeyCalls, 0);
      expect(platform.signCalls, 1);
      expect(result.strongBoxFallback, isTrue);
      expect(result.securityLevel, 'TRUSTED_ENVIRONMENT');
      expect(result.code, startsWith('YANJIR1.'));
    });

    test('creates a device key only after explicit request when get-only is missing', () async {
      final platform = _FakeLicensePlatform(key: _key(), missingKey: true);

      await LicenseActivationRequestBuilder.create(
        platform: platform,
        clock: () => DateTime.utc(2026, 11, 24),
        random: Random(7),
      );

      expect(platform.getKeyCalls, 1);
      expect(platform.createKeyCalls, 1);
      expect(platform.signCalls, 1);
    });

    test('emits canonical protocol fields and a 32-byte request nonce', () async {
      final platform = _FakeLicensePlatform(key: _key());

      final result = await LicenseActivationRequestBuilder.create(
        platform: platform,
        clock: () => DateTime.utc(2026, 11, 24, 9, 30, 15),
        random: Random(1234),
      );

      final parts = result.code.split('.');
      expect(parts, hasLength(3));
      expect(parts.first, 'YANJIR1');
      expect(parts[1], platform.signedPayload);
      expect(parts[2], 'MEUCIQDsignature');

      final payloadBytes = base64Url.decode(
        parts[1].padRight(parts[1].length + (4 - parts[1].length % 4) % 4, '='),
      );
      final payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      expect(payload['schema_version'], 1);
      expect(payload['app_id'], 'com.nihaisha.nihaisha_app');
      expect(payload['product_id'], 'yanji_pro_lifetime');
      expect(payload['issued_at'], '2026-11-24T09:30:15.000Z');
      expect(payload['device_public_key_spki'], _key().spkiDerBase64Url);
      expect(payload['device_key_sha256'], _key().sha256Base64Url);
      expect(payload['device_key_security_level'], 'TRUSTED_ENVIRONMENT');
      expect(
        base64Url.decode(
          (payload['request_nonce'] as String).padRight(
            (payload['request_nonce'] as String).length +
                (4 - (payload['request_nonce'] as String).length % 4) % 4,
            '=',
          ),
        ),
        hasLength(32),
      );
      expect(
        payload['request_id'],
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(
        utf8.decode(payloadBytes),
        utf8.decode(LicenseVerifier.canonicalJsonBytes(payload)),
      );
      expect(result.requestId, payload['request_id']);
      expect(result.deviceFingerprint, _key().sha256Base64Url);
    });

    test('does not continue when existing key read fails for a reason other than missing', () async {
      final platform = _ThrowingLicensePlatform(key: _key());

      await expectLater(
        LicenseActivationRequestBuilder.create(
          platform: platform,
          random: Random(1),
        ),
        throwsA(
          isA<LicensePlatformFailure>().having(
            (error) => error.code,
            'code',
            'keystoreUnavailable',
          ),
        ),
      );
      expect(platform.createKeyCalls, 0);
    });

    test('rejects a non-canonical device fingerprint before signing', () async {
      final platform = _FakeLicensePlatform(
        key: DeviceKeyInfo(
          spkiDerBase64Url: 'spki',
          sha256Base64Url: 'not-a-fingerprint',
          securityLevel: 'UNKNOWN',
        ),
      );

      await expectLater(
        LicenseActivationRequestBuilder.create(
          platform: platform,
          random: Random(2),
        ),
        throwsFormatException,
      );
      expect(platform.signCalls, 0);
    });
  });
}

class _ThrowingLicensePlatform extends _FakeLicensePlatform {
  _ThrowingLicensePlatform({required DeviceKeyInfo key}) : super(key: key);

  @override
  Future<DeviceKeyInfo> getDeviceKey() async {
    getKeyCalls++;
    throw const LicensePlatformFailure('keystoreUnavailable');
  }
}
