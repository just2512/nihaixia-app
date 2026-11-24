import 'dart:async';

import '../models/ai_context_ref.dart';
import 'ai_context_resolver.dart';

/// Outcomes of validating a persisted contextual source reference.
enum ContextResolutionGatewayStatus {
  referenceValidated,
  resolved,
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
    this.reason,
  });

  final ContextResolutionGatewayStatus status;
  final T? value;
  final String? reason;

  bool get isReferenceValid =>
      status == ContextResolutionGatewayStatus.referenceValidated ||
      status == ContextResolutionGatewayStatus.resolved;

  bool get isResolved =>
      status == ContextResolutionGatewayStatus.resolved && value != null;
}

/// Validates contextual source references and binds Resolver results to the
/// exact requested anchor. It is not a licensing or paid-feature boundary.
///
/// The Native LiteRT Gate separately controls whether any resolved context may
/// be submitted to a model. Deterministic source resolution stays available
/// without an AI runtime entitlement.
class ContextResolutionGateway {
  const ContextResolutionGateway();

  /// Validates a persisted reference without resolving its source.
  ///
  /// Suitable for history restoration and the preflight for each subsequent
  /// model turn. A missing or malformed reference is never inferred.
  Future<ContextResolutionGatewayResult<void>> validateReference(
    AiContextRef reference,
  ) async {
    if (!_isValidReference(reference)) {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_REFERENCE_INVALID',
      );
    }
    return const ContextResolutionGatewayResult<void>(
      status: ContextResolutionGatewayStatus.referenceValidated,
    );
  }

  /// Parses persisted metadata and validates only a complete, valid anchor.
  Future<ContextResolutionGatewayResult<void>> validateMetadata(
    Map<String, String>? metadata,
  ) async {
    final reference = AiContextRef.fromMetadata(metadata);
    if (reference == null) {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_METADATA_MISSING_OR_INVALID',
      );
    }
    return validateReference(reference);
  }

  /// Validates and resolves one source-bound contextual reference.
  ///
  /// The resolver callback is deliberately invoked only after the requested
  /// reference passes structural validation. [referenceOf] binds its returned
  /// value back to the exact requested anchor so stale or cross-context values
  /// cannot be submitted to a model.
  Future<ContextResolutionGatewayResult<T>> resolve<T>({
    required AiContextRef reference,
    required FutureOr<AiContextResolution<T>> Function() resolver,
    required AiContextRef Function(T value) referenceOf,
  }) async {
    final validation = await validateReference(reference);
    if (!validation.isReferenceValid) {
      return ContextResolutionGatewayResult<T>(
        status: validation.status,
        reason: validation.reason,
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
}
