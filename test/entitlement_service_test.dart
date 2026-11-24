import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';
import 'package:nihaisha_app/licensing/license_model.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';
import 'support/fake_ai_model_access_platform.dart';

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

  setUpAll(() async {
    vectors = await _loadVector();
    licenseFixture = vectors['valid_license'] as Map<String, dynamic>;
    fingerprint =
        (licenseFixture['payload'] as Map<String, dynamic>)['device_public_key_sha256']
            as String;
    validToken = licenseFixture['token'] as String;
  });

  group('EntitlementService', () {
    test('missing Token is unlicensed and never reads or creates a device key', () async {
      final platform = _FakeLicensePlatform();
      final service = EntitlementService(
        platform: platform,
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(service.snapshot.failureReason,
          FeatureAuthorizationFailureReason.keyMissing);
      expect(platform.keyCreateCount, 0);
      service.dispose();
    });

    test('valid shared Token grants only the two enforced first-release features', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.active);
      expect(service.snapshot.aiAccess, isTrue);
      expect(platform.keyReadCount, 1);
      expect(platform.challengeCount, 1);
      expect(platform.keyCreateCount, 0);

      final ai = await service.authorize('ai_advanced');
      final contextual = await service.authorize('contextual_assistant');
      final learning = await service.authorize('advanced_learning');

      expect(ai.status, FeatureAuthorizationStatus.allowed);
      expect(contextual.status, FeatureAuthorizationStatus.allowed);
      expect(learning.status, FeatureAuthorizationStatus.denied);
      expect(learning.reason,
          FeatureAuthorizationFailureReason.featureNotGranted);
      service.dispose();
    });

    test('unknown issuer is invalid and does not grant a feature', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors, trustIssuer: false),
      );

      final decision = await service.authorize('ai_advanced');

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(decision.status, FeatureAuthorizationStatus.denied);
      expect(decision.reason, FeatureAuthorizationFailureReason.issuerUnknown);
      expect(service.snapshot.aiAccess, isFalse);
      service.dispose();
    });

    test('corrupt storage is invalid but temporary storage unavailability is not', () async {
      final corrupt = _FakeLicensePlatform(
        failure: const LicensePlatformFailure('STORE_CORRUPT'),
      );
      final corruptService = EntitlementService(
        platform: corrupt,
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );
      await corruptService.initialize();
      expect(corruptService.snapshot.status, EntitlementServiceStatus.invalid);
      expect(corruptService.snapshot.failureReason,
          FeatureAuthorizationFailureReason.storeCorrupt);

      final unavailable = _FakeLicensePlatform(
        failure: const LicensePlatformFailure('STORAGE_UNAVAILABLE'),
      );
      final unavailableService = EntitlementService(
        platform: unavailable,
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );
      final decision = await unavailableService.authorize('ai_advanced');
      expect(unavailableService.snapshot.status,
          EntitlementServiceStatus.temporarilyUnavailable);
      expect(decision.status,
          FeatureAuthorizationStatus.temporarilyUnavailable);
      expect(decision.reason,
          FeatureAuthorizationFailureReason.storageUnavailable);
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
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

    test('invalid replacement does not overwrite the existing Token', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final service = EntitlementService(
        platform: platform,
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );
      await service.initialize();

      final invalid = await service.replaceToken(
        token: validToken.substring(0, validToken.length - 1) +
            (validToken.endsWith('A') ? 'B' : 'A'),
        allowFeatureReduction: true,
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );

      final result = await service.replaceToken(
        token: validToken,
        allowFeatureReduction: false,
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: _verifier(vectors),
      );

      await service.initialize();

      expect(service.snapshot.status, EntitlementServiceStatus.invalid);
      expect(
        service.snapshot.failureReason,
        FeatureAuthorizationFailureReason.keyInvalidated,
      );
      expect(platform.keyCreateCount, 0);
      service.dispose();
    });

    test('revision-1 claim consolidation does not trigger a false AI downgrade', () async {
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
        aiModelAccessPlatform: FakeAiModelAccessPlatform(),
        verifier: verifier,
      );
      await service.initialize();

      final installed = await service.replaceToken(
        token: reducedToken,
        allowFeatureReduction: false,
      );
      expect(installed.status, LicenseTokenReplacementStatus.installed);
      expect(installed.status, LicenseTokenReplacementStatus.installed);
      expect(platform.writeCount, 1);
      expect(platform.token, reducedToken);
      expect(service.snapshot.aiAccess, isTrue);
      service.dispose();
    });


    test('effective AI access downgrade requires confirmation and then closes Native gate', () async {
      final platform = _FakeLicensePlatform(
        token: validToken,
        deviceKey: _deviceKey(fingerprint),
      );
      final baseVerifier = _verifier(vectors);
      final payload = LicensePayload.fromJson({
        ...licenseFixture['payload'] as Map<String, dynamic>,
        'features': ['advanced_learning'],
      });
      const noAccessToken = 'test-no-ai-access-token';
      final verifier = _SelectiveLicenseVerifier(
        delegate: baseVerifier,
        replacementToken: noAccessToken,
        replacementResult: LicenseVerificationResult(
          LicenseVerificationStatus.validWithoutGrantedFeatures,
          payload,
        ),
      );
      final aiAccessPlatform = FakeAiModelAccessPlatform();
      final service = EntitlementService(
        platform: platform,
        aiModelAccessPlatform: aiAccessPlatform,
        verifier: verifier,
      );
      await service.initialize();
      expect(service.snapshot.aiAccess, isTrue);
      expect(aiAccessPlatform.enabled, isTrue);

      final confirmation = await service.replaceToken(
        token: noAccessToken,
        allowFeatureReduction: false,
      );
      expect(confirmation.status, LicenseTokenReplacementStatus.confirmationRequired);
      expect(confirmation.lostFeatureIds, {'ai_access'});
      expect(platform.writeCount, 0);
      expect(platform.token, validToken);

      final installed = await service.replaceToken(
        token: noAccessToken,
        allowFeatureReduction: true,
      );
      expect(installed.status, LicenseTokenReplacementStatus.installed);
      expect(platform.token, noAccessToken);
      expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
      expect(service.snapshot.aiAccess, isFalse);
      expect(aiAccessPlatform.enabled, isFalse);
      expect(aiAccessPlatform.transitions.last, isFalse);
      service.dispose();
    });

  });
}