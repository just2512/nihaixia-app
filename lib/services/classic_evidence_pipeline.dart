import '../models/ai_evidence.dart';
import 'classic_search_service.dart';

/// Collects bundled classic-index candidates without changing the established
/// query sequence, hit ordering, deduplication key, or four-hit context output.
///
/// This is the recall boundary only. Ranking remains the legacy implicit order
/// in this slice and is deliberately not reinterpreted as a relevance score.
class ClassicEvidencePipeline {
  static const int legacyContextHitLimit = 4;

  static int _requestSequence = 0;

  static String nextRequestId() =>
      'classic-index-request-${++_requestSequence}';

  static Future<CandidateEvidenceBatch> retrieveClassicIndexCandidates({
    required String requestId,
    required String originalQuery,
    required List<DerivedEvidenceQuery> derivedQueries,
  }) async {
    final candidates = <CandidateEvidence>[];
    final seenIdentities = <String>{};
    final diagnostics = <String>[];
    var partial = false;
    var failed = false;

    for (var queryIndex = 0; queryIndex < derivedQueries.length; queryIndex++) {
      final derivedQuery = derivedQueries[queryIndex];
      if (derivedQuery.query.trim().length < 2) continue;

      try {
        final result = await ClassicSearchService.search(derivedQuery.query);
        if (result.total > result.hits.length) {
          partial = true;
          diagnostics.add(
            'CLASSIC_INDEX_HIT_CAP:${derivedQuery.queryId}:'
            '${result.hits.length}/${result.total}',
          );
        }

        // Consume the complete returned hit page for this query. The legacy
        // context materializer still takes the first four candidates below,
        // so current user-visible order and content remain unchanged.
        for (final hit in result.hits) {
          final identity =
              '${hit.source}|${hit.asset ?? hit.bookId}|'
              '${hit.chapterIndex}|${hit.title}';
          if (!seenIdentities.add(identity)) continue;

          final sourceId = hit.sourceId;
          final evidenceIndex = candidates.length + 1;
          candidates.add(
            CandidateEvidence(
              evidenceId: '$requestId:candidate:$evidenceIndex',
              sourceId: sourceId,
              sourceVersion: 'UNKNOWN',
              origin: CandidateEvidenceOrigin.appData,
              materialKind: hit.asset != null
                  ? 'lecture'
                  : hit.bookId != null
                      ? 'classic_text'
                      : 'UNKNOWN',
              verificationStatus: 'UNKNOWN',
              assetId: hit.asset,
              chunkId: hit.bookId == null
                  ? null
                  : '${hit.bookId}:${hit.chapterIndex ?? 'MISSING'}',
              title: hit.title,
              chapterPath: hit.bookId == null
                  ? null
                  : 'guji:${hit.bookId}#chapter:${hit.chapterIndex ?? 'MISSING'}',
              locator: hit.localBacklink,
              locatorStatus: hit.locatorStatus,
              excerpt: hit.snippet,
              queryId: derivedQuery.queryId,
              retrievalMethod: 'CLASSIC_SUBSTRING_INDEX',
              matchBasis: 'UNKNOWN',
              completeness: CandidateEvidenceCompleteness.unknown,
              sourceKey: hit.source,
              sourceLabel: hit.sourceLabel,
              localBacklink: hit.localBacklink,
              hasLocalBacklink: hit.hasLocalBacklink,
              bookId: hit.bookId,
              chapterIndex: hit.chapterIndex,
            ),
          );
        }

        if (candidates.length >= legacyContextHitLimit) {
          if (queryIndex + 1 < derivedQueries.length) {
            partial = true;
            diagnostics.add(
              'LEGACY_QUERY_EARLY_STOP_AFTER_FOUR:${derivedQuery.queryId}',
            );
          }
          break;
        }
      } catch (_) {
        failed = true;
        diagnostics.add('CLASSIC_SEARCH_FAILED:${derivedQuery.queryId}');
        break;
      }
    }

    final CandidateEvidenceBatchStatus status;
    if (candidates.isEmpty) {
      status = failed
          ? CandidateEvidenceBatchStatus.failed
          : CandidateEvidenceBatchStatus.missing;
    } else if (failed || partial) {
      status = CandidateEvidenceBatchStatus.partial;
    } else {
      status = CandidateEvidenceBatchStatus.retrieved;
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
