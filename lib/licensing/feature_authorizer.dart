/// Asynchronous authorization contract shared by all protected capabilities.
///
/// This interface deliberately contains no licensing-store, Android, UI or
/// global-singleton dependency. Feature dispatchers and context gateways inject
/// an implementation; tests can provide a deterministic fake.
enum FeatureAuthorizationStatus {
  allowed,
  denied,
  temporarilyUnavailable,
}

/// Stable diagnostic reasons for a feature authorization decision.
///
/// A temporary inability to verify authorization is distinct from an
/// unlicensed result. Callers must not persist a temporary denial as a
/// permanent entitlement state.
enum FeatureAuthorizationFailureReason {
  initializationTimeout,
  unlicensed,
  featureNotGranted,
  storeCorrupt,
  storageUnavailable,
  issuerUnknown,
  signatureInvalid,
  unsupportedRevision,
  deviceMismatch,
  keyMissing,
  keyInvalidated,
  keystoreUnavailable,
  providerError,
  licenseRevoked,
  issuerCompromised,
  invalidTokenFormat,
  wrongApplication,
  wrongProduct,
}

/// Diagnostic-only protocol condition. This is not a reason to reject an
/// otherwise valid signed token or to deny unrelated recognized features.
enum FeatureAuthorizationDiagnostic {
  unsupportedFeatureClaim,
}

class FeatureAuthorizationDecision {
  const FeatureAuthorizationDecision._({
    required this.featureId,
    required this.status,
    this.reason,
  });

  final String featureId;
  final FeatureAuthorizationStatus status;
  final FeatureAuthorizationFailureReason? reason;

  bool get isAllowed => status == FeatureAuthorizationStatus.allowed;

  factory FeatureAuthorizationDecision.allowed({
    required String featureId,
  }) {
    _validateFeatureId(featureId);
    return FeatureAuthorizationDecision._(
      featureId: featureId,
      status: FeatureAuthorizationStatus.allowed,
    );
  }

  factory FeatureAuthorizationDecision.denied({
    required String featureId,
    required FeatureAuthorizationFailureReason reason,
  }) {
    _validateFeatureId(featureId);
    return FeatureAuthorizationDecision._(
      featureId: featureId,
      status: FeatureAuthorizationStatus.denied,
      reason: reason,
    );
  }

  factory FeatureAuthorizationDecision.temporarilyUnavailable({
    required String featureId,
    required FeatureAuthorizationFailureReason reason,
  }) {
    _validateFeatureId(featureId);
    return FeatureAuthorizationDecision._(
      featureId: featureId,
      status: FeatureAuthorizationStatus.temporarilyUnavailable,
      reason: reason,
    );
  }

  static void _validateFeatureId(String featureId) {
    if (featureId.trim().isEmpty || featureId != featureId.trim()) {
      throw ArgumentError.value(
        featureId,
        'featureId',
        'Feature ID must be non-empty and already trimmed.',
      );
    }
  }
}

/// Injected authorization query. Implementations must be asynchronous so a
/// caller can await initial verification under the bounded-wait policy.
abstract interface class FeatureAuthorizer {
  Future<FeatureAuthorizationDecision> authorize(String featureId);
}

/// Fail-closed fallback for internal callers that do not yet have a production
/// entitlement scope. It never grants a feature and has no Flutter dependency.
class DenyByDefaultFeatureAuthorizer implements FeatureAuthorizer {
  const DenyByDefaultFeatureAuthorizer();

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    return FeatureAuthorizationDecision.denied(
      featureId: featureId,
      reason: FeatureAuthorizationFailureReason.unlicensed,
    );
  }
}
