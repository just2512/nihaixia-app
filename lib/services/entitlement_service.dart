import 'dart:async';

import 'package:flutter/foundation.dart';

import '../licensing/ai_model_access_platform.dart';
import '../licensing/license_model.dart';
import '../licensing/license_platform.dart';
import '../licensing/license_verifier.dart';

enum EntitlementServiceStatus {
  checking,
  active,
  unlicensed,
  temporarilyUnavailable,
  invalid,
}

class EntitlementSnapshot {
  EntitlementSnapshot({
    required this.status,
    this.aiAccess = false,
    Iterable<String> unsupportedFeatureIds = const [],
    this.failureReason,
    this.lastCheckedAt,
    this.licenseId,
    this.issuerKeyId,
  }) : unsupportedFeatureIds =
           Set<String>.unmodifiable(unsupportedFeatureIds);

  final EntitlementServiceStatus status;

  /// The only effective App runtime entitlement. No per-business Feature set
  /// is retained or persisted.
  final bool aiAccess;
  final Set<String> unsupportedFeatureIds;
  final LicenseFailureReason? failureReason;

  /// Diagnostic only. Never used to decide perpetual-license validity.
  final DateTime? lastCheckedAt;
  final String? licenseId;
  final String? issuerKeyId;

  bool get isActive => status == EntitlementServiceStatus.active;
}

enum LicenseTokenReplacementStatus {
  installed,
  confirmationRequired,
  rejected,
  temporarilyUnavailable,
  storageFailure,
  busy,
}

class LicenseTokenReplacementResult {
  const LicenseTokenReplacementResult({
    required this.status,
    this.verification,
    this.failureReason,
    this.lostFeatureIds = const {},
  });

  final LicenseTokenReplacementStatus status;
  final LicenseVerificationResult? verification;
  final LicenseFailureReason? failureReason;
  final Set<String> lostFeatureIds;

  bool get installed => status == LicenseTokenReplacementStatus.installed;
}

class EntitlementService extends ChangeNotifier {
  EntitlementService({
    required LicensePlatform platform,
    required LicenseVerifier verifier,
    required AiModelAccessPlatform aiModelAccessPlatform,
    this.initializationTimeout = const Duration(seconds: 2),
  })  : _platform = platform,
        _verifier = verifier,
        _aiModelAccessPlatform = aiModelAccessPlatform;

  final LicensePlatform _platform;
  final LicenseVerifier _verifier;
  final AiModelAccessPlatform _aiModelAccessPlatform;
  final Duration initializationTimeout;

  EntitlementSnapshot _snapshot = EntitlementSnapshot(
    status: EntitlementServiceStatus.checking,
  );
  EntitlementSnapshot get snapshot => _snapshot;

  Future<void>? _initializationFuture;
  bool _initialized = false;
  bool _replacementInProgress = false;
  int _generation = 0;
  bool _disposed = false;

  /// One shared initial verification. Once it completes, later authorization
  /// checks use the in-memory snapshot until an explicit refresh is requested.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _startRefresh();
  }

  /// Explicitly re-reads and re-verifies the active Token from private storage.
  Future<void> refresh() {
    _initialized = false;
    return _startRefresh(supersedeInFlight: true);
  }

  Future<void> _startRefresh({bool supersedeInFlight = false}) {
    final inFlight = _initializationFuture;
    if (inFlight != null && !supersedeInFlight) return inFlight;

    final future = _refreshFromPlatform();
    _initializationFuture = future;
    return future.whenComplete(() {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
        _initialized = true;
      }
    });
  }

  Future<void> _refreshFromPlatform() async {
    final generation = ++_generation;
    _publish(
      EntitlementSnapshot(status: EntitlementServiceStatus.checking),
    );

    try {
      // A refresh closes access before examining the Token. All checking,
      // invalid, missing and temporarily unavailable states remain fail-closed.
      await _aiModelAccessPlatform
          .setEnabled(false)
          .timeout(initializationTimeout);
      if (generation != _generation) return;

      final token = await _platform.readActiveToken();
      if (token == null) {
        _publishIfCurrent(
          generation,
          EntitlementSnapshot(
            status: EntitlementServiceStatus.unlicensed,
            lastCheckedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }

      // Existing Tokens never cause key creation. Missing/invalidated keys are
      // explicit invalid states, not a signal to silently bind a new device.
      final deviceKey = await _platform.getDeviceKey();
      final challengeKey = await _platform.checkPrivateKeyUsability();
      if (!_sameDeviceKey(deviceKey, challengeKey)) {
        _publishIfCurrent(
          generation,
          _invalid(LicenseFailureReason.keyInvalidated),
        );
        return;
      }

      final result = await _verifier.verify(
        token,
        expectedDevicePublicKeySha256: deviceKey.sha256Base64Url,
      );
      final verifiedSnapshot = _snapshotFromVerification(result);

      if (generation != _generation) return;
      if (verifiedSnapshot.aiAccess) {
        try {
          await _aiModelAccessPlatform
              .setEnabled(true)
              .timeout(initializationTimeout);
        } on Object {
          // An uncertain enable acknowledgement must not leave Native open.
          try {
            await _aiModelAccessPlatform
                .setEnabled(false)
                .timeout(initializationTimeout);
          } on Object {
            // The service remains unavailable; Native still owns the hard gate.
          }
          rethrow;
        }
      }
      _publishIfCurrent(generation, verifiedSnapshot);
    } on LicensePlatformFailure catch (error) {
      _publishIfCurrent(generation, _snapshotForPlatformFailure(error));
    } on Object {
      _publishIfCurrent(
        generation,
        _temporarilyUnavailable(
          LicenseFailureReason.providerError,
        ),
      );
    }
  }

  bool _sameDeviceKey(DeviceKeyInfo first, DeviceKeyInfo second) =>
      first.sha256Base64Url == second.sha256Base64Url &&
      first.spkiDerBase64Url == second.spkiDerBase64Url;

  EntitlementSnapshot _snapshotFromVerification(
    LicenseVerificationResult result,
  ) {
    final now = DateTime.now().toUtc();
    final payload = result.payload;
    switch (result.status) {
      case LicenseVerificationStatus.valid:
      case LicenseVerificationStatus.validWithUnsupportedFeatures:
        final aiAccess = payload?.grantsAiAccess == true;
        return EntitlementSnapshot(
          status: aiAccess
              ? EntitlementServiceStatus.active
              : EntitlementServiceStatus.unlicensed,
          aiAccess: aiAccess,
          failureReason: aiAccess
              ? null
              : LicenseFailureReason.featureNotGranted,
          unsupportedFeatureIds: payload?.unsupportedFeatureIds ?? const [],
          lastCheckedAt: now,
          licenseId: payload?.licenseId,
          issuerKeyId: payload?.issuerKeyId,
        );
      case LicenseVerificationStatus.validWithoutGrantedFeatures:
        // This is an authenticated, well-formed Token with no AI entitlement.
        // It may be installed after explicit confirmation of an AI downgrade.
        return EntitlementSnapshot(
          status: EntitlementServiceStatus.unlicensed,
          failureReason: LicenseFailureReason.featureNotGranted,
          unsupportedFeatureIds: payload?.unsupportedFeatureIds ?? const [],
          lastCheckedAt: now,
          licenseId: payload?.licenseId,
          issuerKeyId: payload?.issuerKeyId,
        );
      case LicenseVerificationStatus.unknownIssuer:
        return _invalid(LicenseFailureReason.issuerUnknown);
      case LicenseVerificationStatus.issuerCompromised:
        return _invalid(LicenseFailureReason.issuerCompromised);
      case LicenseVerificationStatus.invalidSignature:
      case LicenseVerificationStatus.invalidIssuerKey:
        return _invalid(LicenseFailureReason.signatureInvalid);
      case LicenseVerificationStatus.unsupportedRevision:
      case LicenseVerificationStatus.unsupportedSchema:
        return _invalid(LicenseFailureReason.unsupportedRevision);
      case LicenseVerificationStatus.wrongDevice:
        return _invalid(LicenseFailureReason.deviceMismatch);
      case LicenseVerificationStatus.revoked:
        return _invalid(LicenseFailureReason.licenseRevoked);
      case LicenseVerificationStatus.invalidFormat:
      case LicenseVerificationStatus.invalidPayload:
        return _invalid(LicenseFailureReason.invalidTokenFormat);
      case LicenseVerificationStatus.wrongProduct:
        return _invalid(LicenseFailureReason.wrongProduct);
      case LicenseVerificationStatus.wrongApplication:
        return _invalid(LicenseFailureReason.wrongApplication);
    }
  }

  EntitlementSnapshot _invalid(LicenseFailureReason reason) =>
      EntitlementSnapshot(
        status: EntitlementServiceStatus.invalid,
        failureReason: reason,
        lastCheckedAt: DateTime.now().toUtc(),
      );

  EntitlementSnapshot _temporarilyUnavailable(
    LicenseFailureReason reason,
  ) =>
      EntitlementSnapshot(
        status: EntitlementServiceStatus.temporarilyUnavailable,
        failureReason: reason,
        lastCheckedAt: DateTime.now().toUtc(),
      );

  EntitlementSnapshot _snapshotForPlatformFailure(
    LicensePlatformFailure error,
  ) {
    switch (error.code) {
      case 'keyMissing':
      case 'KEY_MISSING':
        return _invalid(LicenseFailureReason.keyMissing);
      case 'keyInvalidated':
      case 'KEY_INVALIDATED':
        return _invalid(LicenseFailureReason.keyInvalidated);
      case 'storeCorrupt':
      case 'STORE_CORRUPT':
        return _invalid(LicenseFailureReason.storeCorrupt);
      case 'storageUnavailable':
      case 'STORAGE_UNAVAILABLE':
      case 'TOKEN_READ_FAILED':
        return _temporarilyUnavailable(
          LicenseFailureReason.storageUnavailable,
        );
      case 'keystoreUnavailable':
      case 'KEYSTORE_UNAVAILABLE':
        return _temporarilyUnavailable(
          LicenseFailureReason.keystoreUnavailable,
        );
      case 'providerError':
      case 'PROVIDER_ERROR':
      case 'platformUnavailable':
      case 'PLATFORM_UNAVAILABLE':
        return _temporarilyUnavailable(
          LicenseFailureReason.providerError,
        );
      default:
        return _temporarilyUnavailable(
          LicenseFailureReason.providerError,
        );
    }
  }

  void _publishIfCurrent(int generation, EntitlementSnapshot snapshot) {
    if (generation == _generation) _publish(snapshot);
  }

  void _publish(EntitlementSnapshot snapshot) {
    if (_disposed) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  /// Verifies the complete incoming token before storage access. A reduction
  /// requires an explicit confirmation supplied by the caller/UI.
  Future<LicenseTokenReplacementResult> replaceToken({
    required String token,
    required bool allowFeatureReduction,
  }) async {
    if (_replacementInProgress) {
      return const LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.busy,
      );
    }
    _replacementInProgress = true;

    String? previousToken;
    var writeAttempted = false;
    LicenseVerificationResult? verification;
    try {
      await initialize().timeout(initializationTimeout);
      if (_snapshot.status == EntitlementServiceStatus.temporarilyUnavailable ||
          _snapshot.status == EntitlementServiceStatus.checking) {
        return LicenseTokenReplacementResult(
          status: LicenseTokenReplacementStatus.temporarilyUnavailable,
          failureReason: _snapshot.failureReason ??
              LicenseFailureReason.initializationTimeout,
        );
      }

      final deviceKey = await _platform.getDeviceKey();
      final challengeKey = await _platform.checkPrivateKeyUsability();
      if (!_sameDeviceKey(deviceKey, challengeKey)) {
        return const LicenseTokenReplacementResult(
          status: LicenseTokenReplacementStatus.rejected,
          failureReason: LicenseFailureReason.keyInvalidated,
        );
      }

      verification = await _verifier.verify(
        token,
        expectedDevicePublicKeySha256: deviceKey.sha256Base64Url,
      );
      if (!verification.isAuthenticated || verification.payload == null) {
        return LicenseTokenReplacementResult(
          status: LicenseTokenReplacementStatus.rejected,
          verification: verification,
        );
      }

      previousToken = await _platform.readActiveToken();
      final losesAiAccess =
          _snapshot.aiAccess && !verification.payload!.grantsAiAccess;
      if (losesAiAccess && !allowFeatureReduction) {
        return LicenseTokenReplacementResult(
          status: LicenseTokenReplacementStatus.confirmationRequired,
          verification: verification,
          lostFeatureIds: const {'ai_access'},
        );
      }

      writeAttempted = true;
      await _platform.writeActiveTokenAtomically(token);
      await refresh().timeout(initializationTimeout);
      final persisted =
          _snapshot.licenseId == verification.payload!.licenseId &&
          _snapshot.status != EntitlementServiceStatus.invalid &&
          _snapshot.status != EntitlementServiceStatus.temporarilyUnavailable &&
          _snapshot.status != EntitlementServiceStatus.checking;
      if (!persisted) {
        await _restorePreviousToken(previousToken);
        return LicenseTokenReplacementResult(
          status: LicenseTokenReplacementStatus.rejected,
          verification: verification,
          failureReason: _snapshot.failureReason,
        );
      }
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.installed,
        verification: verification,
      );
    } on TimeoutException {
      if (writeAttempted) await _restorePreviousToken(previousToken);
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.temporarilyUnavailable,
        verification: verification,
        failureReason: LicenseFailureReason.initializationTimeout,
      );
    } on LicensePlatformFailure catch (error) {
      if (writeAttempted) await _restorePreviousToken(previousToken);
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.storageFailure,
        verification: verification,
        failureReason: _reasonForPlatformFailure(error),
      );
    } on Object {
      if (writeAttempted) await _restorePreviousToken(previousToken);
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.storageFailure,
        verification: verification,
        failureReason: LicenseFailureReason.providerError,
      );
    } finally {
      _replacementInProgress = false;
    }
  }

  LicenseFailureReason _reasonForPlatformFailure(
    LicensePlatformFailure error,
  ) {
    final temporary = _snapshotForPlatformFailure(error);
    return temporary.failureReason ??
        LicenseFailureReason.providerError;
  }

  Future<void> _restorePreviousToken(String? previousToken) async {
    try {
      if (previousToken == null) {
        await _platform.deleteActiveToken();
      } else {
        await _platform.writeActiveTokenAtomically(previousToken);
      }
      // Supersede any still-running verification of the rejected replacement.
      // Generation checks prevent that stale result from publishing after the
      // old token has been restored.
      _initialized = false;
      await _startRefresh(supersedeInFlight: true);
    } on Object {
      _publish(
        _temporarilyUnavailable(
          LicenseFailureReason.storageUnavailable,
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
