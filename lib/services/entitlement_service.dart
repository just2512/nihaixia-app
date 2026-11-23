import 'dart:async';

import 'package:flutter/foundation.dart';

import '../licensing/feature_authorizer.dart';
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
    Iterable<String> grantedFeatureIds = const [],
    Iterable<String> unsupportedFeatureIds = const [],
    this.failureReason,
    this.lastCheckedAt,
    this.licenseId,
    this.issuerKeyId,
  })  : grantedFeatureIds = Set<String>.unmodifiable(grantedFeatureIds),
        unsupportedFeatureIds =
            Set<String>.unmodifiable(unsupportedFeatureIds);

  final EntitlementServiceStatus status;
  final Set<String> grantedFeatureIds;
  final Set<String> unsupportedFeatureIds;
  final FeatureAuthorizationFailureReason? failureReason;
  final DateTime? lastCheckedAt;
  final String? licenseId;
  final String? issuerKeyId;

  bool get isActive => status == EntitlementServiceStatus.active;
}

enum LicenseTokenReplacementStatus {
  installed,
  confirmationRequired,
  rejected,
  storageFailure,
}

class LicenseTokenReplacementResult {
  const LicenseTokenReplacementResult({
    required this.status,
    required this.verification,
  });

  final LicenseTokenReplacementStatus status;
  final LicenseVerificationResult verification;

  bool get installed => status == LicenseTokenReplacementStatus.installed;
}

class EntitlementService extends ChangeNotifier
    implements FeatureAuthorizer {
  EntitlementService({
    required LicensePlatform platform,
    required LicenseVerifier verifier,
    this.initializationTimeout = const Duration(seconds: 2),
  })  : _platform = platform,
        _verifier = verifier;

  final LicensePlatform _platform;
  final LicenseVerifier _verifier;
  final Duration initializationTimeout;

  EntitlementSnapshot _snapshot = EntitlementSnapshot(
    status: EntitlementServiceStatus.checking,
  );
  EntitlementSnapshot get snapshot => _snapshot;

  Future<void>? _initializationFuture;
  int _generation = 0;
  bool _disposed = false;

  /// Starts one shared verification operation. It never throws into app startup.
  Future<void> initialize() {
    final inFlight = _initializationFuture;
    if (inFlight != null) return inFlight;

    final future = _refresh();
    _initializationFuture = future;
    return future.whenComplete(() {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    });
  }

  /// Explicitly reloads and re-verifies the current Token.
  Future<void> refresh() => initialize();

  Future<void> _refresh() async {
    final generation = ++_generation;
    _publish(EntitlementSnapshot(status: EntitlementServiceStatus.checking));

    try {
      final token = await _platform.readActiveToken();
      if (token == null || token.isEmpty) {
        _publishIfCurrent(
          generation,
          EntitlementSnapshot(
            status: EntitlementServiceStatus.unlicensed,
            lastCheckedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }

      final deviceKey = await _platform.getDeviceKey();
      await _platform.checkPrivateKeyUsability();
      final result = await _verifier.verify(
        token,
        expectedDevicePublicKeySha256: deviceKey.sha256Base64Url,
      );
      _publishIfCurrent(generation, _snapshotFromVerification(result));
    } on LicensePlatformFailure catch (error) {
      _publishIfCurrent(
        generation,
        _snapshotForPlatformFailure(error),
      );
    } on Object {
      _publishIfCurrent(
        generation,
        EntitlementSnapshot(
          status: EntitlementServiceStatus.temporarilyUnavailable,
          failureReason: FeatureAuthorizationFailureReason.providerError,
          lastCheckedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  EntitlementSnapshot _snapshotFromVerification(
    LicenseVerificationResult result,
  ) {
    final now = DateTime.now().toUtc();
    final payload = result.payload;
    switch (result.status) {
      case LicenseVerificationStatus.valid:
      case LicenseVerificationStatus.validWithUnsupportedFeatures:
        return EntitlementSnapshot(
          status: EntitlementServiceStatus.active,
          grantedFeatureIds: payload?.grantedFeatureIds ?? const [],
          unsupportedFeatureIds: payload?.unsupportedFeatureIds ?? const [],
          lastCheckedAt: now,
          licenseId: payload?.licenseId,
          issuerKeyId: payload?.issuerKeyId,
        );
      case LicenseVerificationStatus.validWithoutGrantedFeatures:
        return EntitlementSnapshot(
          status: EntitlementServiceStatus.invalid,
          failureReason: FeatureAuthorizationFailureReason.featureNotGranted,
          unsupportedFeatureIds: payload?.unsupportedFeatureIds ?? const [],
          lastCheckedAt: now,
          licenseId: payload?.licenseId,
          issuerKeyId: payload?.issuerKeyId,
        );
      case LicenseVerificationStatus.unknownIssuer:
        return _invalid(FeatureAuthorizationFailureReason.issuerUnknown);
      case LicenseVerificationStatus.issuerCompromised:
        return _invalid(FeatureAuthorizationFailureReason.issuerCompromised);
      case LicenseVerificationStatus.invalidSignature:
      case LicenseVerificationStatus.invalidIssuerKey:
        return _invalid(FeatureAuthorizationFailureReason.signatureInvalid);
      case LicenseVerificationStatus.unsupportedRevision:
      case LicenseVerificationStatus.unsupportedSchema:
        return _invalid(FeatureAuthorizationFailureReason.unsupportedRevision);
      case LicenseVerificationStatus.wrongDevice:
        return _invalid(FeatureAuthorizationFailureReason.deviceMismatch);
      case LicenseVerificationStatus.revoked:
        return _invalid(FeatureAuthorizationFailureReason.licenseRevoked);
      case LicenseVerificationStatus.invalidFormat:
      case LicenseVerificationStatus.invalidPayload:
        return _invalid(FeatureAuthorizationFailureReason.invalidTokenFormat);
      case LicenseVerificationStatus.wrongProduct:
        return _invalid(FeatureAuthorizationFailureReason.wrongProduct);
      case LicenseVerificationStatus.wrongApplication:
        return _invalid(FeatureAuthorizationFailureReason.wrongApplication);
    }
  }

  EntitlementSnapshot _invalid(FeatureAuthorizationFailureReason reason) =>
      EntitlementSnapshot(
        status: EntitlementServiceStatus.invalid,
        failureReason: reason,
        lastCheckedAt: DateTime.now().toUtc(),
      );

  EntitlementSnapshot _snapshotForPlatformFailure(
    LicensePlatformFailure error,
  ) {
    switch (error.code) {
      case 'KEY_MISSING':
        return _invalid(FeatureAuthorizationFailureReason.keyMissing);
      case 'KEY_INVALIDATED':
        return _invalid(FeatureAuthorizationFailureReason.keyInvalidated);
      case 'STORE_CORRUPT':
        return EntitlementSnapshot(
          status: EntitlementServiceStatus.invalid,
          failureReason: FeatureAuthorizationFailureReason.storeCorrupt,
          lastCheckedAt: DateTime.now().toUtc(),
        );
      case 'STORAGE_UNAVAILABLE':
      case 'TOKEN_READ_FAILED':
        return _temporarilyUnavailable(
          FeatureAuthorizationFailureReason.storageUnavailable,
        );
      case 'KEYSTORE_UNAVAILABLE':
        return _temporarilyUnavailable(
          FeatureAuthorizationFailureReason.keystoreUnavailable,
        );
      default:
        return _temporarilyUnavailable(
          FeatureAuthorizationFailureReason.providerError,
        );
    }
  }

  EntitlementSnapshot _temporarilyUnavailable(
    FeatureAuthorizationFailureReason reason,
  ) =>
      EntitlementSnapshot(
        status: EntitlementServiceStatus.temporarilyUnavailable,
        failureReason: reason,
        lastCheckedAt: DateTime.now().toUtc(),
      );

  void _publishIfCurrent(int generation, EntitlementSnapshot snapshot) {
    if (generation == _generation) _publish(snapshot);
  }

  void _publish(EntitlementSnapshot snapshot) {
    if (_disposed) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    if (featureId.trim().isEmpty || featureId != featureId.trim()) {
      throw ArgumentError.value(featureId, 'featureId');
    }

    try {
      await initialize().timeout(initializationTimeout);
    } on TimeoutException {
      return FeatureAuthorizationDecision.temporarilyUnavailable(
        featureId: featureId,
        reason: FeatureAuthorizationFailureReason.initializationTimeout,
      );
    } on Object {
      return FeatureAuthorizationDecision.temporarilyUnavailable(
        featureId: featureId,
        reason: FeatureAuthorizationFailureReason.providerError,
      );
    }

    final current = _snapshot;
    if (current.status == EntitlementServiceStatus.active &&
        current.grantedFeatureIds.contains(featureId)) {
      return FeatureAuthorizationDecision.allowed(featureId: featureId);
    }
    if (current.status == EntitlementServiceStatus.temporarilyUnavailable ||
        current.status == EntitlementServiceStatus.checking) {
      return FeatureAuthorizationDecision.temporarilyUnavailable(
        featureId: featureId,
        reason: current.failureReason ??
            FeatureAuthorizationFailureReason.providerError,
      );
    }
    return FeatureAuthorizationDecision.denied(
      featureId: featureId,
      reason: current.failureReason ??
          (current.status == EntitlementServiceStatus.unlicensed
              ? FeatureAuthorizationFailureReason.unlicensed
              : FeatureAuthorizationFailureReason.featureNotGranted),
    );
  }

  /// Validates a replacement before touching disk. A reduction requires an
  /// explicit affirmative parameter supplied by a user-confirmed UI flow.
  Future<LicenseTokenReplacementResult> replaceToken({
    required String token,
    required bool allowFeatureReduction,
  }) async {
    final deviceKey = await _platform.getDeviceKey();
    await _platform.checkPrivateKeyUsability();
    final next = await _verifier.verify(
      token,
      expectedDevicePublicKeySha256: deviceKey.sha256Base64Url,
    );
    if (!next.isValid || next.payload == null) {
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.rejected,
        verification: next,
      );
    }

    final previousToken = await _platform.readActiveToken();
    final oldFeatures = _snapshot.grantedFeatureIds;
    final nextFeatures = next.payload!.grantedFeatureIds;
    final reducesEntitlements = oldFeatures.difference(nextFeatures).isNotEmpty;
    if (reducesEntitlements && !allowFeatureReduction) {
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.confirmationRequired,
        verification: next,
      );
    }

    try {
      await _platform.writeActiveTokenAtomically(token);
      await refresh();
      final persisted =
          _snapshot.isActive && _snapshot.licenseId == next.payload!.licenseId;
      if (!persisted) {
        await _restorePreviousToken(previousToken);
        return LicenseTokenReplacementResult(
          status: LicenseTokenReplacementStatus.rejected,
          verification: next,
        );
      }
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.installed,
        verification: next,
      );
    } on Object {
      await _restorePreviousToken(previousToken);
      return LicenseTokenReplacementResult(
        status: LicenseTokenReplacementStatus.storageFailure,
        verification: next,
      );
    }
  }

  Future<void> _restorePreviousToken(String? previousToken) async {
    if (previousToken == null) {
      await _platform.deleteActiveToken();
    } else {
      await _platform.writeActiveTokenAtomically(previousToken);
    }
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
