import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';
import 'package:nihaisha_app/licensing/license_model.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';

class _FakeLicensePlatform implements LicensePlatform {
  _FakeLicensePlatform({
    this.token,
    this.deviceKey,
    this.readCompleter,
    this.failure,
  });

  String? token;
  DeviceKeyInfo? deviceKey;
  Completer<String?>? readCompleter;
  LicensePlatformFailure? failure;
  String? writtenToken;
  int readCount = 0;
  int keyReadCount = 0;
  int challengeCount = 0;
  int keyCreateCount = 0;

  @override
  Future<String?> readActiveToken() async {
    readCount++;
    if (failure != null) throw failure!;
    if (readCompleter != null) return readCompleter!.future;
    return token;
  }

  @override
  Future<void> writeActiveTokenAtomically(String token) async {
    if (failure != null) throw failure!;
    writtenToken = token;
    this.token = token;
  }

  @override
  Future<void> deleteActiveToken() async {
    token = null;
  }

  @override
  Future<DeviceKeyInfo> getDeviceKey() async {
    keyReadCount++;
    if (failure != null) throw failure!;
    final value = deviceKey;
    if (value == null) {
      throw const LicensePlatformFailure('KEY_MISSING');
    }
    return value;
  }

  @override
  Future<DeviceKeyInfo> createDeviceKeyForActivation() async {
    keyCreateCount++;
    final value = deviceKey;
    if (value == null) {
      throw const LicensePlatformFailure('KEY_MISSING');
    }
    return value;
  }

  @override
  Future<void> checkPrivateKeyUsability() async {
    challengeCount++;
    if (failure != null) throw failure!;
  }
}

LicenseVerifier _verifier() => LicenseVerifier(
      keyRing: LicenseKeyRing(keys: const []),
    );

DeviceKeyInfo _deviceKey() => const DeviceKeyInfo(
      spkiDerBase64Url: 'spki',
      sha256Base64Url: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      securityLevel: 'UNKNOWN',
    );

void main() {
  group('EntitlementService', () {
    test('missing token is unlicensed and never creates a device key', () async {
      final platform = _FakeLicensePlatform(deviceKey: _deviceKey());
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(),
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      expect(platform.keyReadCount, 0);
      expect(platform.keyCreateCount, 0);
      service.dispose();
    });

    test('missing key for existing token is a precise invalid state', () async {
      final platform = _FakeLicensePlatform(token: 'YANJI1.invalid.invalid');
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(),
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(
        service.snapshot.failureReason,
        FeatureAuthorizationFailureReason.keyMissing,
      );
      expect(platform.keyCreateCount, 0);
      service.dispose();
    });

    test('concurrent initialization calls share one storage read', () async {
      final completer = Completer<String?>();
      final platform = _FakeLicensePlatform(
        readCompleter: completer,
        deviceKey: _deviceKey(),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(),
      );

      final a = service.initialize();
      final b = service.initialize();
      expect(platform.readCount, 1);

      completer.complete(null);
      await Future.wait([a, b]);
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      service.dispose();
    });

    test('temporary storage failure remains unavailable and free functions stay usable', () async {
      final platform = _FakeLicensePlatform(
        failure: const LicensePlatformFailure('STORAGE_UNAVAILABLE'),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(),
      );

      final decision = await service.authorize('ai_advanced');

      expect(service.snapshot.status,
          EntitlementServiceStatus.temporarilyUnavailable);
      expect(decision.status,
          FeatureAuthorizationStatus.temporarilyUnavailable);
      expect(decision.reason,
          FeatureAuthorizationFailureReason.storageUnavailable);
      service.dispose();
    });

    test('initialization timeout is temporary and does not rewrite service state', () async {
      final completer = Completer<String?>();
      final platform = _FakeLicensePlatform(
        readCompleter: completer,
        deviceKey: _deviceKey(),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(),
        initializationTimeout: const Duration(milliseconds: 5),
      );

      final decision = await service.authorize('ai_advanced');

      expect(decision.status,
          FeatureAuthorizationStatus.temporarilyUnavailable);
      expect(decision.reason,
          FeatureAuthorizationFailureReason.initializationTimeout);
      expect(service.snapshot.status, EntitlementServiceStatus.checking);
      completer.complete(null);
      await service.initialize();
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      service.dispose();
    });

    test('unknown issuer never grants a feature', () async {
      final platform = _FakeLicensePlatform(
        token: 'YANJI1.eyJpc3N1ZXJfa2V5X2lkIjoidW5rbm93biJ9.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        deviceKey: _deviceKey(),
      );
      final service = EntitlementService(
        platform: platform,
        verifier: _verifier(),
      );

      final decision = await service.authorize('ai_advanced');

      expect(decision.status, FeatureAuthorizationStatus.denied);
      expect(decision.reason, FeatureAuthorizationFailureReason.issuerUnknown);
      expect(service.snapshot.grantedFeatureIds, isEmpty);
      service.dispose();
    });
  });
}
