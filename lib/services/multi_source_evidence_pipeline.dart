import '../models/ai_evidence.dart';

/// Combines independently retrieved source batches into one request-scoped
/// candidate collection without ranking or changing source order.
///
/// Callers must pass batches in the established presentation/compatibility
/// order (for example: classic index, requested Guji books, then medical cases).
/// This class preserves that order; it does not infer source priority.
class MultiSourceEvidencePipeline {
  static CandidateEvidenceBatch combine({
    required String requestId,
    required String originalQuery,
    required List<CandidateEvidenceBatch> sourceBatches,
  }) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }
    if (originalQuery.trim().isEmpty) {
      throw ArgumentError.value(
        originalQuery,
        'originalQuery',
        'Must not be empty',
      );
    }

    if (sourceBatches.isEmpty) {
      return CandidateEvidenceBatch(
        requestId: requestId,
        originalQuery: originalQuery,
        derivedQueries: const [],
        status: CandidateEvidenceBatchStatus.missing,
        candidates: const [],
        diagnostics: const ['NO_SOURCE_BATCHES'],
      );
    }

    final seenBatchIds = <String>{};
    final seenQueryIds = <String>{};
    final seenEvidenceIds = <String>{};
    final derivedQueries = <DerivedEvidenceQuery>[];
    final candidates = <CandidateEvidence>[];
    final diagnostics = <String>[];

    var hasFailed = false;
    var hasUnknown = false;
    var hasPartial = false;

    for (final batch in sourceBatches) {
      if (batch.requestId.trim().isEmpty) {
        throw StateError('Source batch requestId must not be empty');
      }
      if (!seenBatchIds.add(batch.requestId)) {
        throw StateError('Duplicate source batch requestId: ${batch.requestId}');
      }
      if (batch.originalQuery != originalQuery) {
        throw StateError(
          'Source batch ${batch.requestId} belongs to a different original query',
        );
      }

      final namespacedQueryIds = <String, String>{};
      for (final query in batch.derivedQueries) {
        if (query.queryId.trim().isEmpty) {
          throw StateError(
            'Source batch ${batch.requestId} has an empty derived queryId',
          );
        }
        final namespacedId = '${batch.requestId}:${query.queryId}';
        if (!seenQueryIds.add(namespacedId)) {
          throw StateError('Duplicate derived queryId: $namespacedId');
        }
        namespacedQueryIds[query.queryId] = namespacedId;
        derivedQueries.add(query.copyWith(queryId: namespacedId));
      }

      for (final candidate in batch.candidates) {
        if (candidate.evidenceId.trim().isEmpty) {
          throw StateError(
            'Source batch ${batch.requestId} contains an empty evidenceId',
          );
        }
        final namespacedEvidenceId =
            '$requestId:${batch.requestId}:${candidate.evidenceId}';
        if (!seenEvidenceIds.add(namespacedEvidenceId)) {
          throw StateError('Duplicate combined evidenceId: $namespacedEvidenceId');
        }
        final queryId = namespacedQueryIds[candidate.queryId];
        if (queryId == null) {
          throw StateError(
            'Candidate ${candidate.evidenceId} references unmapped queryId '
            '${candidate.queryId} in batch ${batch.requestId}',
          );
        }
        candidates.add(
          candidate.copyWith(
            evidenceId: namespacedEvidenceId,
            queryId: queryId,
          ),
        );
      }

      hasFailed = hasFailed ||
          batch.status == CandidateEvidenceBatchStatus.failed;
      hasUnknown = hasUnknown ||
          batch.status == CandidateEvidenceBatchStatus.unknown;
      hasPartial = hasPartial ||
          batch.status == CandidateEvidenceBatchStatus.partial;
      diagnostics.addAll(
        batch.diagnostics.map((item) => '${batch.requestId}:$item'),
      );
    }

    final CandidateEvidenceBatchStatus status;
    if (candidates.isNotEmpty) {
      status = hasFailed || hasUnknown || hasPartial
          ? CandidateEvidenceBatchStatus.partial
          : CandidateEvidenceBatchStatus.retrieved;
    } else if (hasFailed) {
      status = CandidateEvidenceBatchStatus.failed;
    } else if (hasUnknown) {
      status = CandidateEvidenceBatchStatus.unknown;
    } else if (hasPartial) {
      status = CandidateEvidenceBatchStatus.partial;
    } else {
      status = CandidateEvidenceBatchStatus.missing;
    }

    return CandidateEvidenceBatch(
      requestId: requestId,
      originalQuery: originalQuery,
      derivedQueries: derivedQueries,
      status: status,
      candidates: candidates,
      diagnostics: diagnostics,
    );
  }
}
