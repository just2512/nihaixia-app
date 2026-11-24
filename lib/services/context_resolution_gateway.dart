import 'dart:async';

import '../models/ai_context_ref.dart';
import 'ai_context_resolver.dart';

/// Outcomes from validating a persisted source anchor and resolving its source.
/// This gateway protects provenance and anchor integrity, never paid access.
enum ContextResolutionGatewayStatus {
  validReference,
  resolved,
  invalidReference,
  missing,
  unknown,
  stale,
  sourceDenied,
  resolverFailure,
}

class ContextResolutionGatewayResult<T> {
  const ContextResolutionGatewayResult({required this.status, this.value, this.reason});
  final ContextResolutionGatewayStatus status;
  final T? value;
  final String? reason;

  bool get isValidReference =>
      status == ContextResolutionGatewayStatus.validReference ||
      status == ContextResolutionGatewayStatus.resolved;
  bool get isResolved => status == ContextResolutionGatewayStatus.resolved && value != null;
}

class ContextResolutionGateway {
  const ContextResolutionGateway();

  Future<ContextResolutionGatewayResult<void>> validateReference(AiContextRef reference) async {
    if (!_isValidReference(reference)) {
      return const ContextResolutionGatewayResult<void>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_REFERENCE_INVALID',
      );
    }
    return const ContextResolutionGatewayResult<void>(
      status: ContextResolutionGatewayStatus.validReference,
    );
  }

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

  Future<ContextResolutionGatewayResult<T>> resolve<T>({
    required AiContextRef reference,
    required FutureOr<AiContextResolution<T>> Function() resolver,
    required AiContextRef Function(T value) referenceOf,
  }) async {
    if (!_isValidReference(reference)) {
      return const ContextResolutionGatewayResult<T>(
        status: ContextResolutionGatewayStatus.invalidReference,
        reason: 'CONTEXT_REFERENCE_INVALID',
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
        AiContextResolutionStatus.resolved => ContextResolutionGatewayStatus.unknown,
        AiContextResolutionStatus.missing => ContextResolutionGatewayStatus.missing,
        AiContextResolutionStatus.unknown => ContextResolutionGatewayStatus.unknown,
        AiContextResolutionStatus.stale => ContextResolutionGatewayStatus.stale,
        AiContextResolutionStatus.denied => ContextResolutionGatewayStatus.sourceDenied,
      };
      return ContextResolutionGatewayResult<T>(
        status: status,
        reason: resolution.reason ?? resolution.status.name,
      );
    }
    try {
      final resolvedReference = referenceOf(resolution.value as T);
      if (!_sameReference(resolvedReference, reference)) {
        return const ContextResolutionGatewayResult<T>(
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
    if (normalized.isEmpty || normalized.length != metadata.length) return false;
    const requiredKeys = ['moduleId', 'anchorId', 'anchorVersion', 'sourceId'];
    if (requiredKeys.any(
      (key) => metadata[key]?.trim().isNotEmpty != true ||
          metadata[key] != metadata[key]!.trim(),
    )) return false;
    for (final key in const ['snapshotId', 'ruleVersion', 'fieldPath']) {
      final value = metadata[key];
      if (value != null && (value.isEmpty || value != value.trim())) return false;
    }
    return _sameReference(reference, reference);
  }

  bool _sameReference(AiContextRef left, AiContextRef right) =>
      AiContextRef.matchesSameAnchor(left.toMetadata(), right.toMetadata());
}
