import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/services/multi_source_evidence_pipeline.dart';

CandidateEvidence _candidate({
  required String id,
  required String queryId,
  String method = 'CLASSIC_SUBSTRING_INDEX',
  String? bookId,
  String sourceId = 'source:1',
}) =>
    CandidateEvidence(
      evidenceId: id,
      sourceId: sourceId,
      origin: CandidateEvidenceOrigin.appData,
      materialKind: 'test',
      title: id,
      excerpt: 'excerpt',
      queryId: queryId,
      retrievalMethod: method,
      matchBasis: 'TEST',
      completeness: CandidateEvidenceCompleteness.complete,
      sourceKey: 'test',
      sourceLabel: '测试来源',
      localBacklink: 'MISSING',
      hasLocalBacklink: false,
      bookId: bookId,
    );

CandidateEvidenceBatch _batch({
  required String requestId,
  required List<DerivedEvidenceQuery> queries,
  List<CandidateEvidence> candidates = const [],
  CandidateEvidenceBatchStatus status = CandidateEvidenceBatchStatus.retrieved,
  String originalQuery = '原始查询',
}) =>
    CandidateEvidenceBatch(
      requestId: requestId,
      originalQuery: originalQuery,
      derivedQueries: queries,
      status: status,
      candidates: candidates,
      diagnostics: const [],
    );

void main() {
  test('combines source batches in caller order and namespaces query/evidence IDs', () {
    final classic = _batch(
      requestId: 'classic-1',
      queries: [DerivedEvidenceQuery(queryId: 'q1', query: '经典', reasons: const [])],
      candidates: [_candidate(id: 'classic-hit-1', queryId: 'q1')],
    );
    final medical = _batch(
      requestId: 'medical-1',
      queries: [DerivedEvidenceQuery(queryId: 'q1', query: '医案', reasons: const [])],
      candidates: [
        _candidate(
          id: 'case-hit-1',
          queryId: 'q1',
          method: 'MEDICAL_CASE_NORMALIZED_TEXT_MATCH',
          sourceId: 'medical_case:1',
        ),
      ],
    );

    final combined = MultiSourceEvidencePipeline.combine(
      requestId: 'combined-request',
      originalQuery: '原始查询',
      sourceBatches: [classic, medical],
    );

    expect(combined.status, CandidateEvidenceBatchStatus.retrieved);
    expect(combined.candidates.map((item) => item.sourceId), [
      'source:1',
      'medical_case:1',
    ]);
    expect(combined.candidates.map((item) => item.queryId), [
      'classic-1:q1',
      'medical-1:q1',
    ]);
    expect(combined.derivedQueries.map((item) => item.queryId), [
      'classic-1:q1',
      'medical-1:q1',
    ]);
    expect(combined.candidates.first.evidenceId, contains('classic-1:classic-hit-1'));
    expect(combined.candidates.last.evidenceId, contains('medical-1:case-hit-1'));
  });

  test('keeps partial source availability visible when other sources return candidates', () {
    final retrieved = _batch(
      requestId: 'classic-1',
      queries: [DerivedEvidenceQuery(queryId: 'q1', query: '经典', reasons: const [])],
      candidates: [_candidate(id: 'hit-1', queryId: 'q1')],
    );
    final failed = _batch(
      requestId: 'guji-1',
      queries: const [],
      status: CandidateEvidenceBatchStatus.failed,
    );

    final combined = MultiSourceEvidencePipeline.combine(
      requestId: 'combined-request',
      originalQuery: '原始查询',
      sourceBatches: [retrieved, failed],
    );

    expect(combined.status, CandidateEvidenceBatchStatus.partial);
    expect(combined.candidates, hasLength(1));
  });

  test('returns FAILED rather than MISSING when every source failed', () {
    final combined = MultiSourceEvidencePipeline.combine(
      requestId: 'combined-request',
      originalQuery: '原始查询',
      sourceBatches: [
        _batch(
          requestId: 'classic-1',
          queries: const [],
          status: CandidateEvidenceBatchStatus.failed,
        ),
        _batch(
          requestId: 'guji-1',
          queries: const [],
          status: CandidateEvidenceBatchStatus.failed,
        ),
      ],
    );

    expect(combined.status, CandidateEvidenceBatchStatus.failed);
    expect(combined.candidates, isEmpty);
  });

  test('returns MISSING when all sources completed without a match', () {
    final combined = MultiSourceEvidencePipeline.combine(
      requestId: 'combined-request',
      originalQuery: '原始查询',
      sourceBatches: [
        _batch(
          requestId: 'classic-1',
          queries: const [],
          status: CandidateEvidenceBatchStatus.missing,
        ),
        _batch(
          requestId: 'medical-1',
          queries: const [],
          status: CandidateEvidenceBatchStatus.missing,
        ),
      ],
    );

    expect(combined.status, CandidateEvidenceBatchStatus.missing);
  });

  test('rejects duplicate batch identities and cross-query batches', () {
    final first = _batch(requestId: 'same', queries: const []);
    expect(
      () => MultiSourceEvidencePipeline.combine(
        requestId: 'combined',
        originalQuery: '原始查询',
        sourceBatches: [first, first],
      ),
      throwsStateError,
    );
    expect(
      () => MultiSourceEvidencePipeline.combine(
        requestId: 'combined',
        originalQuery: '另一个查询',
        sourceBatches: [first],
      ),
      throwsStateError,
    );
  });

  test('rejects candidate references without a query mapping', () {
    final invalid = _batch(
      requestId: 'classic-1',
      queries: const [],
      candidates: [_candidate(id: 'hit-1', queryId: 'missing-query')],
    );
    expect(
      () => MultiSourceEvidencePipeline.combine(
        requestId: 'combined',
        originalQuery: '原始查询',
        sourceBatches: [invalid],
      ),
      throwsStateError,
    );
  });
}
