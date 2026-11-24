import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/ai_model_access_platform.dart';
import 'package:nihaisha_app/licensing/entitlement_failure_reason.dart';
import 'package:nihaisha_app/licensing/license_model.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';

class _FakeAiModelAccessPlatform implements AiModelAccessPlatform {
  final states = <bool>[];
  bool failNextCall = false;

  @override
  Future<void> setAiAccess(bool allowed) async {
    states.add(allowed);
    if (failNextCall) {
      failNextCall = false;
      throw const AiModelAccessPlatformFailure('testFailure');
    }
  }
}

class _FakeLicensePlatform implements LicensePlatform {
  _FakeLicensePlatform({
    this.token,
    this.deviceKey,
    this.challengeDeviceKey,
    this.readCompleter,
    this.failure,
  });

  String? token;
  DeviceKeyInfo? deviceKey;
  DeviceKeyInfo? challengeDeviceKey;
  Completer<String?>? readCompleter;
  LicensePlatformFailure? failure;
  String? writtenToken;
  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  int keyReadCount = 0;
  int challengeCount = 0;
  int keyCreateCount = 0;

  @override
  Future<String?> readActiveToken() async {
    readCount++;
    if (failure != null) throw failure!;
    final pending = readCompleter;
    if (pending != null) return pending.future;
    return token;
  }

  @override
  Future<void> writeActiveTokenAtomically(String token) async {
    if (failure != null) throw failure!;
    writeCount++;
    writtenToken = token;
    this.token = token;
  }

  @override
  Future<void> deleteActiveToken() async {
    deleteCount++;
    token = null;
  }

  @override
  Future<DeviceKeyInfo> getDeviceKey() async {
    keyReadCount++;
    if (failure != null) throw failure!;
    final value = deviceKey;
    if (value == null) throw const LicensePlatformFailure('KEY_MISSING');
    return value;
  }

  @override
  Future<DeviceKeyInfo> createDeviceKeyForActivation() async {
    keyCreateCount++;
    final value = deviceKey;
    if (value == null) throw const LicensePlatformFailure('KEY_MISSING');
    return value;
  }

  @override
  Future<String> signActivationRequest(String payloadBase64Url) async =>
      'test-signature';

  @override
  Future<DeviceKeyInfo> checkPrivateKeyUsability() async {
    challengeCount++;
    if (failure != null) throw failure!;
    final value = challengeDeviceKey ?? deviceKey;
    if (value == null) throw const LicensePlatformFailure('keyMissing');
    return value;
  }
}

class _SelectiveLicenseVerifier extends LicenseVerifier {
  _SelectiveLicenseVerifier({
    required this.delegate,
    required this.replacementToken,
    required this.replacementResult,
  }) : super(keyRing: LicenseKeyRing(keys: const []));

  final LicenseVerifier delegate;
  final String replacementToken;
  final LicenseVerificationResult replacementResult;

  @override
  Future<LicenseVerificationResult> verify(
    String token, {
    required String expectedDevicePublicKeySha256,
    String expectedAppId = yanjiLicenseAppId,
  }) {
    if (token == replacementToken) {
      return Future.value(replacementResult);
    }
    return delegate.verify(
      token,
      expectedDevicePublicKeySha256: expectedDevicePublicKeySha256,
      expectedAppId: expectedAppId,
    );
  }
}

List<int> _decodeBase64Url(String value) {
  final normalized = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return base64Url.decode(normalized);
}

Future<Map<String, dynamic>> _loadVector() async {
  final file = File('test/fixtures/pro-license-test-vectors.json');
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

LicenseVerifier _verifier(Map<String, dynamic> vectors, {bool trustIssuer = true}) {
  final keys = <LicenseIssuerKey>[];
  if (trustIssuer) {
    keys.add(
      LicenseIssuerKey(
        keyId: vectors['issuer_key_id'] as String,
        publicKey: _decodeBase64Url(
          vectors['issuer_public_key_raw_base64url'] as String,
        ),
        status: LicenseIssuerKeyStatus.active,
      ),
    );
  }
  return LicenseVerifier(keyRing: LicenseKeyRing(keys: keys));
}

DeviceKeyInfo _deviceKey(String fingerprint) => DeviceKeyInfo(
      spkiDerBase64Url: 'test-spki-not-used-for-token-verification',
      sha256Base64Url: fingerprint,
      securityLevel: 'UNKNOWN',
    );

void main() {
  late Map<String, dynamic> vectors;
  late Map<String, dynamic> licenseFixture;
  late String fingerprint;
  late String validToken;
  late _FakeAiModelAccessPlatform aiModelAccessPlatform;

  setUp(() {
    aiModelAccessPlatform = _FakeAiModelAccessPlatform();
  });

  setUpAll(() async {
    vectors = await _loadVector();
    licenseFixture = vectors['valid_license'] as Map<String, dynamic>;
    fingerprint =
        (licenseFixture['payload'] as Map<String, dynamic>)['device_public_key_sha256']
            as String;
    validToken = licenseFixture['token'] as String;
  });

  group('EntitlementService', () {
    test('verified historical Token opens the Native gate after verification', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(aiModelAccessPlatform.states, [false, true]);
      expect(service.snapshot.aiAccess, isTrue);
      service.dispose();
    });

    test('missing Token leaves the Native gate closed', () async {
      final platform = _FakeLicensePlatform();
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(aiModelAccessPlatform.states, [false]);
      expect(service.snapshot.aiAccess, isFalse);
      service.dispose();
    });

    test('Native bridge failure prevents publishing active entitlement', () async {
      aiModelAccessPlatform.failNextCall = true;
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(
        service.snapshot.status,
        EntitlementServiceStatus.temporarilyUnavailable,
      );
      expect(service.snapshot.aiAccess, isFalse);
      service.dispose();
    });


    test('missing Token is unlicensed and never reads or creates a device key', () async {
      final platform = _FakeLicensePlatform();
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      expect(platform.readCount, 1);
      expect(platform.keyReadCount, 0);
      expect(platform.keyCreateCount, 0);
      expect(platform.challengeCount, 0);
      service.dispose();
    });

    test('existing Token with missing key is invalid and never recreates the key', () async {
      final platform = _FakeLicensePlatform(token: validToken);
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(service.snapshot.failureReason,
          EntitlementFailureReason.keyMissing);
      expect(platform.keyCreateCount, 0);
      service.dispose();
    });

    test('valid historical Token maps both legacy claims to one effective AI entitlement', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.active);
      expect(service.snapshot.aiAccess, isTrue);
      expect(platform.keyReadCount, 1);
      expect(platform.challengeCount, 1);
      expect(platform.keyCreateCount, 0);

      expect(service.snapshot.aiAccess, isTrue);
      service.dispose();
    });

    test('unknown issuer is invalid and does not grant a feature', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors, trustIssuer: false),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(service.snapshot.failureReason, EntitlementFailureReason.issuerUnknown);
      expect(service.snapshot.aiAccess, isFalse);
      service.dispose();
    });

    test('corrupt storage is invalid but temporary storage unavailability is not', () async {
      final corrupt = _FakeLicensePlatform(
        failure: const LicensePlatformFailure('STORE_CORRUPT'),
      );
      final corruptService = EntitlementService(
        platform: corrupt,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );
      await corruptService.initialize();
      expect(corruptService.snapshot.status, EntitlementServiceStatus.invalid);
      expect(corruptService.snapshot.failureReason,
          EntitlementFailureReason.storeCorrupt);

      final unavailable = _FakeLicensePlatform(
        failure: const LicensePlatformFailure('STORAGE_UNAVAILABLE'),
      );
      final unavailableService = EntitlementService(
        platform: unavailable,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );
      await unavailableService.initialize();
      expect(unavailableService.snapshot.status,
          EntitlementServiceStatus.temporarilyUnavailable);
      expect(unavailableService.snapshot.failureReason,
          EntitlementFailureReason.storageUnavailable);
      expect(unavailableService.snapshot.aiAccess, isFalse);
      corruptService.dispose();
      unavailableService.dispose();
    });

    test('concurrent initialization calls share one storage read', () async {
      final completer = Completer<String?>();
      final platform = _FakeLicensePlatform(
        readCompleter: completer,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      final first = service.initialize();
      final second = service.initialize();
      expect(platform.readCount, 1);

      completer.complete(null);
      await Future.wait([first, second]);
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      service.dispose();
    });

    test('initialization timeout is temporary and does not persist a denial', () async {
      final completer = Completer<String?>();
      final platform = _FakeLicensePlatform(
        readCompleter: completer,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
        initializationTimeout: const Duration(milliseconds: 5),
      );

      final initialization = service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.snapshot.status, EntitlementServiceStatus.checking);

      completer.complete(null);
      await initialization;
      await service.initialize();
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      service.dispose();
    });

    test('invalid replacement does not overwrite the existing Token', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );
      await service.initialize();

      final invalid = await service.replaceToken(
        token: validToken.substring(0, validToken.length - 1) +
            (validToken.endsWith('A') ? 'B' : 'A'),
        allowAiAccessDowngrade: true,
      );

      expect(invalid.status, LicenseTokenReplacementStatus.rejected);
      expect(platform.writeCount, 0);
      expect(platform.token, validToken);
      service.dispose();
    });

    test('valid replacement is written atomically and re-read through the platform', () async {
      final platform = _FakeLicensePlatform(
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      final result = await service.replaceToken(
        token: validToken,
        allowAiAccessDowngrade: false,
      );

      expect(result.status, LicenseTokenReplacementStatus.installed);
      expect(platform.writeCount, 1);
      expect(platform.readCount, 3);
      expect(platform.token, validToken);
      expect(service.snapshot.status, EntitlementServiceStatus.active);
      service.dispose();
    });
    test('explicit refresh supersedes an initialization still in flight', () async {
      final completer = Completer<String?>();
      final platform = _FakeLicensePlatform(readCompleter: completer);
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      final first = service.initialize();
      expect(platform.readCount, 1);

      platform.readCompleter = null;
      await service.refresh();
      expect(platform.readCount, 2);
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);

      completer.complete(null);
      await first;
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      service.dispose();
    });

    test('completed initialization is cached until explicit refresh', () async {
      final platform = _FakeLicensePlatform();
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();
      await service.initialize();
      expect(platform.readCount, 1);

      await service.refresh();
      expect(platform.readCount, 2);
      service.dispose();
    });

    test('private-key challenge must match the retrieved device key', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
        challengeDeviceKey: _deviceKey('different-fingerprint'),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(vectors),
        aiModelAccessPlatform: aiModelAccessPlatform,
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(
        service.snapshot.failureReason,
        EntitlementFailureReason.keyInvalidated,
      );
      expect(platform.keyCreateCount, 0);
      service.dispose();
    });

    test('consolidating legacy AI claims does not trigger an effective entitlement downgrade', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final baseVerifier = _verifier(vectors);
      final payload = LicensePayload.fromJson({
        ...licenseFixture['payload'] as Map<String, dynamic>,
        'features': ['ai_advanced'],
      });
      const reducedToken = 'test-reduced-token';
      final verifier = _SelectiveLicenseVerifier(
        delegate: baseVerifier,
        replacementToken: reducedToken,
        replacementResult: LicenseVerificationResult(
          LicenseVerificationStatus.valid,
          payload,
        ),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: verifier,
        aiModelAccessPlatform: aiModelAccessPlatform,
      );
      await service.initialize();

      final installed = await service.replaceToken(
        token: reducedToken,
        allowAiAccessDowngrade: false,
      );
      expect(installed.status, LicenseTokenReplacementStatus.installed);
      expect(installed.losesAiAccess, isFalse);
      expect(installed.status, LicenseTokenReplacementStatus.installed);
      expect(platform.writeCount, 1);
      expect(platform.token, reducedToken);
      expect(service.snapshot.aiAccess, isTrue);
      service.dispose();
    });

  });
}
