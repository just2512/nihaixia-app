import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(yanjiLicenseChannelName);
  late MethodChannelLicensePlatform platform;
  late List<MethodCall> calls;

  setUp(() {
    platform = MethodChannelLicensePlatform(channel: channel);
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void installHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  Map<String, Object?> deviceKeyMap({
    String fingerprint = 'fingerprint-1',
    bool strongBoxFallback = false,
  }) =>
      <String, Object?>{
        'publicKeySpkiBase64Url': 'spki-der-base64url',
        'publicKeySha256': fingerprint,
        'securityLevel': 'TRUSTED_ENVIRONMENT',
        'strongBoxFallback': strongBoxFallback,
      };

  group('MethodChannelLicensePlatform', () {
    test('reads a nullable token through the v1.2 channel method', () async {
      installHandler((call) async {
        expect(call.method, 'readLicenseToken');
        return <String, Object?>{'token': null};
      });

      expect(await platform.readActiveToken(), isNull);
      expect(calls.map((call) => call.method), ['readLicenseToken']);
    });

    test('writes only through the verification-named atomic operation', () async {
      installHandler((call) async {
        expect(call.method, 'writeLicenseTokenAfterVerification');
        expect(call.arguments, {'token': 'YANJI1.payload.signature'});
        return <String, Object?>{'stored': true};
      });

      await platform.writeActiveTokenAtomically('YANJI1.payload.signature');
      expect(calls.single.method, 'writeLicenseTokenAfterVerification');
    });

    test('rejects an unconfirmed native write response', () async {
      installHandler((call) async => <String, Object?>{'stored': false});

      await expectLater(
        platform.writeActiveTokenAtomically('YANJI1.payload.signature'),
        throwsA(
          isA<LicensePlatformFailure>()
              .having((error) => error.code, 'code', 'invalidPlatformResponse'),
        ),
      );
    });

    test('deletes only the Token using the dedicated native operation', () async {
      installHandler((call) async {
        expect(call.method, 'deleteLicenseToken');
        return <String, Object?>{'deleted': true};
      });

      await platform.deleteActiveToken();
      expect(calls.single.method, 'deleteLicenseToken');
    });

    test('reads the existing device key and preserves security metadata', () async {
      installHandler((call) async {
        expect(call.method, 'getDeviceKey');
        return deviceKeyMap(strongBoxFallback: true);
      });

      final key = await platform.getDeviceKey();
      expect(key.spkiDerBase64Url, 'spki-der-base64url');
      expect(key.sha256Base64Url, 'fingerprint-1');
      expect(key.securityLevel, 'TRUSTED_ENVIRONMENT');
      expect(key.strongBoxFallback, isTrue);
      expect(calls.single.method, 'getDeviceKey');
    });

    test('creates a device key only through the explicit activation method', () async {
      installHandler((call) async {
        expect(call.method, 'createDeviceKeyForActivation');
        return deviceKeyMap();
      });

      await platform.createDeviceKeyForActivation();
      expect(calls.single.method, 'createDeviceKeyForActivation');
    });

    test('signs the original request payload segment without reserialization', () async {
      installHandler((call) async {
        expect(call.method, 'signActivationRequest');
        expect(call.arguments, {'payloadBase64Url': 'eyJhcHBfaWQiOiJ5YW5qaSJ9'});
        return <String, Object?>{'signatureBase64Url': 'MEUCIQDsignature'};
      });

      expect(
        await platform.signActivationRequest('eyJhcHBfaWQiOiJ5YW5qaSJ9'),
        'MEUCIQDsignature',
      );
    });

    test('challenge check returns the key identity it actually verified', () async {
      installHandler((call) async {
        expect(call.method, 'checkPrivateKeyUsability');
        return deviceKeyMap(fingerprint: 'verified-key');
      });

      final key = await platform.checkPrivateKeyUsability();
      expect(key.sha256Base64Url, 'verified-key');
    });

    test('preserves native error codes for service-level classification', () async {
      installHandler((call) async {
        throw PlatformException(
          code: 'keyMissing',
          message: 'Existing alias is absent.',
        );
      });

      await expectLater(
        platform.getDeviceKey(),
        throwsA(
          isA<LicensePlatformFailure>()
              .having((error) => error.code, 'code', 'keyMissing'),
        ),
      );
    });

    test('maps a missing native plugin to a temporary platform failure', () async {
      await expectLater(
        platform.getDeviceKey(),
        throwsA(
          isA<LicensePlatformFailure>()
              .having((error) => error.code, 'code', 'platformUnavailable'),
        ),
      );
    });
  });
}
