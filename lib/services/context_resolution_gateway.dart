import 'dart:async';

import '../licensing/feature_authorizer.dart';
import '../models/ai_context_ref.dart';
import 'ai_context_resolver.dart';

/// Outcomes at the authorization + source-resolution boundary.
///
/// [authorized] is used by callers that must re-check a persisted context
/// reference before restoring history or sending a new turn. [resolved] is
/// returned only when the resolver supplied a value anchored to the exact
/// requested context reference.
enum ContextResolutionGatewayStatus {
  authorized,
  resolved,
  authorizationDenied,
  authorizationUnavailable,
  invalidReference,
  missing,
  unknown,
  stale,
  sourceDenied,
  resolverFailure,
}

class ContextResolutionGatewayResult<T> {
  const ContextResolutionGatewayResult({
    required this.status,
    this.value,
    this.authorizationReason,
    this.reason,
  });

  final ContextResolutionGatewayStatus status;
  final T? value;
  final FeatureAuthorizationFailureReason? authorizationReason;
  final String? reason;

  bool get isAuthorized =>
      status == ContextResolutionGatewayStatus.authorized ||
      status == ContextResolutionGatewayStatus.resolved;

  bool get isResolved =>
      status == ContextResolutionGatewayStatus.resolved && value != null;
}

/// Single authorization boundary for contextual source resolution.
///
/// The gateway validates the persisted anchor shape first, requests the
/// contextual_assistant entitlement second, and only then invokes a resolver.
/// It is UI-, navigation-, storage-, and platform-independent. Callers must
/// use it before constructing a model prompt and re-check it before every
/// contextual model turn; a previously resolved context is not a perpetual
/// authorization grant.
class ContextResolutionGateway {
  const ContextResolutionGateway({
    required FeatureAuthorizer authorizer,
  }) : _authorizer = authorizer;

  static const featureId = 'contextual_assistant';

  final FeatureAuthorizer _authorizer;

  /// Re-authorizes a context reference without resolving its source.
  ///
  /// Suitable for history restoration and the preflight for each subsequent
  /// turn. A missing or malformed persisted reference is never inferred.
  Future<ContextResolutionGatewayResult<void>> authorizeReference(
    AiContextRef reference,
  ) async {
    if (!_isValidReference(reference)) {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_REFERENCE_INVALID',
      );
    }
    return _authorize();
  }

  /// Parses persisted metadata and authorizes only a complete, valid anchor.
  Future<ContextResolutionGatewayResult<void>> authorizeMetadata(
    Map<String, String>? metadata,
  ) async {
    final reference = AiContextRef.fromMetadata(metadata);
    if (reference == null) {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_METADATA_MISSING_OR_INVALID',
      );
    }
    return authorizeReference(reference);
  }

  /// Authorizes and resolves one source-bound contextual reference.
  ///
  /// The resolver callback is deliberately invoked only after the entitlement
  /// check succeeds. [referenceOf] binds its returned value back to the exact
  /// requested anchor so stale or cross-context values cannot be prompted.
  Future<ContextResolutionGatewayResult<T>> resolve<T>({
    required AiContextRef reference,
    required FutureOr<AiContextResolution<T>> Function() resolver,
    required AiContextRef Function(T value) referenceOf,
  }) async {
    if (!_isValidReference(reference)) {
      return ContextResolutionGatewayResult<T>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_REFERENCE_INVALID',
      );
    }

    final authorization = await _authorize();
    if (!authorization.isAuthorized) {
      return ContextResolutionGatewayResult<T>(
        status: authorization.status,
        authorizationReason: authorization.authorizationReason,
        reason: authorization.reason,
      );
    }

    late final AiContextResolution<T> resolution;
    try {
      resolution = await resolver();
    } on Object catch (error) {
      return ContextResolutionGatewayResult<T>(
        status: ContextResolutionGatewayStatus.resolverFailure,
        reason: error.runtimeType.toString(),
      );
    }

    if (!resolution.isResolved || resolution.value == null) {
      final status = switch (resolution.status) {
        AiContextResolutionStatus.resolved =>
          ContextResolutionGatewayStatus.unknown,
        AiContextResolutionStatus.missing =>
          ContextResolutionGatewayStatus.missing,
        AiContextResolutionStatus.unknown =>
          ContextResolutionGatewayStatus.unknown,
        AiContextResolutionStatus.stale =>
          ContextResolutionGatewayStatus.stale,
        AiContextResolutionStatus.denied =>
          ContextResolutionGatewayStatus.sourceDenied,
      };
      return ContextResolutionGatewayResult<T>(
        status: status,
        reason: resolution.reason ?? resolution.status.name,
      );
    }

    try {
      final resolvedReference = referenceOf(resolution.value as T);
      if (!_sameReference(resolvedReference, reference)) {
        return ContextResolutionGatewayResult<T>(
          status: ContextResolutionGatewayStatus.stale,
          reason: 'RESOLVED_CONTEXT_ANCHOR_MISMATCH',
        );
      }
    } on Object catch (error) {
      return ContextResolutionGatewayResult<T>(
        status: ContextResolutionGatewayStatus.resolverFailure,
        reason: error.runtimeType.toString(),
      );
    }

    return ContextResolutionGatewayResult<T>(
      status: ContextResolutionGatewayStatus.resolved,
      value: resolution.value,
    );
  }

  bool _isValidReference(AiContextRef reference) {
    final metadata = reference.toMetadata();
    final normalized = AiContextRef.normalizeMetadata(metadata);
    if (normalized.isEmpty || normalized.length != metadata.length) {
      return false;
    }
    const requiredKeys = [
      'moduleId',
      'anchorId',
      'anchorVersion',
      'sourceId',
    ];
    if (requiredKeys.any(
      (key) => metadata[key]?.trim().isNotEmpty != true ||
          metadata[key] != metadata[key]!.trim(),
    )) {
      return false;
    }
    for (final key in const ['snapshotId', 'ruleVersion', 'fieldPath']) {
      final value = metadata[key];
      if (value != null && (value.isEmpty || value != value.trim())) {
        return false;
      }
    }
    return _sameReference(reference, reference);
  }

  bool _sameReference(AiContextRef left, AiContextRef right) =>
      AiContextRef.matchesSameAnchor(left.toMetadata(), right.toMetadata());

  Future<ContextResolutionGatewayResult<void>> _authorize() async {
    late final FeatureAuthorizationDecision decision;
    try {
      decision = await _authorizer.authorize(featureId);
    } on Object {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.authorizationUnavailable,
        authorizationReason: FeatureAuthorizationFailureReason.providerError,
        reason: 'AUTHORIZATION_PROVIDER_ERROR',
      );
    }

    if (decision.featureId != featureId) {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.authorizationUnavailable,
        authorizationReason: FeatureAuthorizationFailureReason.providerError,
        reason: 'AUTHORIZATION_FEATURE_MISMATCH',
      );
    }

    return switch (decision.status) {
      FeatureAuthorizationStatus.allowed =>
        const ContextResolutionGatewayResult<void>(
          status: ContextResolutionGatewayStatus.authorized,
        ),
      FeatureAuthorizationStatus.denied =>
        ContextResolutionGatewayResult<void>(
          status: ContextResolutionGatewayStatus.authorizationDenied,
          authorizationReason: decision.reason ??
              FeatureAuthorizationFailureReason.featureNotGranted,
        ),
      FeatureAuthorizationStatus.temporarilyUnavailable =>
        ContextResolutionGatewayResult<void>(
          status: ContextResolutionGatewayStatus.authorizationUnavailable,
          authorizationReason: decision.reason ??
              FeatureAuthorizationFailureReason.providerError,
        ),
    };
  }
}
