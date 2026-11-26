import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/models/evidence_ranking_decision.dart';
import 'package:nihaisha_app/services/source_aware_legacy_evidence_ranker.dart';

CandidateEvidence _candidate({
  required String id,
  required String method,
  String? bookId,
}) =>
    CandidateEvidence(
      evidenceId: id,
      sourceId: 'source:$id',
      origin: CandidateEvidenceOrigin.appData,
      materialKind: 'test',
      title: id,
      excerpt: id,
      queryId: 'q1',
      retrievalMethod: method,
      matchBasis: 'TEST',
      completeness: CandidateEvidenceCompleteness.complete,
      sourceKey: 'test',
      sourceLabel: '测试来源',
      localBacklink: 'MISSING',
      hasLocalBacklink: false,
      bookId: bookId,
    );

void main() {
  test('applies legacy caps per source and preserves aggregate input order', () {
    final candidates = [
      for (var i = 1; i <= 5; i++)
        _candidate(id: 'classic-$i', method: 'CLASSIC_SUBSTRING_INDEX'),
      for (var i = 1; i <= 3; i++)
        _candidate(id: 'medical-$i', method: 'MEDICAL_CASE_NORMALIZED_TEXT_MATCH'),
      for (var i = 1; i <= 3; i++)
        _candidate(id: 'guji-a-$i', method: 'GUIJI_CHAPTER_SUBSTRING_MATCH', bookId: 'a'),
      for (var i = 1; i <= 2; i++)
        _candidate(id: 'guji-b-$i', method: 'GUIJI_CHAPTER_SUBSTRING_MATCH', bookId: 'b'),
    ];

    final ranked = SourceAwareLegacyEvidenceRanker.rank(
      candidates,
      requestId: 'combined',
    );

    expect(ranked.orderedEvidenceIds, [
      'classic-1',
      'classic-2',
      'classic-3',
      'classic-4',
      'medical-1',
      'medical-2',
      'guji-a-1',
      'guji-a-2',
      'guji-b-1',
      'guji-b-2',
    ]);
    expect(
      ranked.decisions.map((item) => item.disposition),
      [
        for (var i = 0; i < 4; i++) EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.drop,
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.drop,
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.drop,
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.keep,
      ],
    );
    expect(ranked.decisions[4].reasonCode, 'LEGACY_CLASSIC_INDEX_FOUR_HIT_LIMIT');
    expect(ranked.decisions[7].reasonCode, 'LEGACY_MEDICAL_CASE_TWO_RESULT_LIMIT');
    expect(ranked.decisions[10].reasonCode, 'LEGACY_GUIJI_TWO_CHAPTER_LIMIT');
    expect(ranked.budget.unit, EvidenceBudgetUnit.unknown);
    expect(ranked.budget.applied, isFalse);
    expect(ranked.budget.limit, isNull);
    expect(ranked.budget.used, isNull);
  });

  test('registers legacy limits for every local structured evidence family', () {
    final candidates = [
      for (var i = 1; i <= 5; i++)
        _candidate(id: 'formula-$i', method: 'LOCAL_FORMULA_LEGACY_MATCH'),
      for (var i = 1; i <= 6; i++)
        _candidate(id: 'herb-$i', method: 'LOCAL_HERB_LEGACY_MATCH'),
      for (var i = 1; i <= 4; i++)
        _candidate(id: 'acupuncture-$i', method: 'LOCAL_ACUPUNCTURE_LEGACY_MATCH'),
      for (var i = 1; i <= 4; i++)
        _candidate(id: 'acupoint-$i', method: 'LOCAL_ACUPOINT_LEGACY_MATCH'),
      for (var i = 1; i <= 4; i++)
        _candidate(id: 'neijing-$i', method: 'LOCAL_NEIJING_LEGACY_MATCH'),
    ];

    final ranked = SourceAwareLegacyEvidenceRanker.rank(
      candidates,
      requestId: 'combined-local',
    );

    expect(ranked.orderedEvidenceIds, [
      for (var i = 1; i <= 4; i++) 'formula-$i',
      for (var i = 1; i <= 5; i++) 'herb-$i',
      for (var i = 1; i <= 3; i++) 'acupuncture-$i',
      for (var i = 1; i <= 3; i++) 'acupoint-$i',
      for (var i = 1; i <= 3; i++) 'neijing-$i',
    ]);
    expect(
      ranked.decisions
          .where((item) => item.disposition == EvidenceDecisionDisposition.drop)
          .map((item) => item.reasonCode),
      [
        'LEGACY_FORMULA_FOUR_ENTRY_LIMIT',
        'LEGACY_HERB_FIVE_ENTRY_LIMIT',
        'LEGACY_ACUPUNCTURE_THREE_ENTRY_LIMIT',
        'LEGACY_ACUPOINT_THREE_ENTRY_LIMIT',
        'LEGACY_NEIJING_THREE_ENTRY_LIMIT',
      ],
    );
    expect(ranked.budget.applied, isFalse);
    expect(ranked.budget.unit, EvidenceBudgetUnit.unknown);
  });

  test('drops unsupported retrieval methods and Guji candidates without book identity', () {
    final ranked = SourceAwareLegacyEvidenceRanker.rank(
      [
        _candidate(id: 'unknown', method: 'UNREGISTERED'),
        _candidate(id: 'guji-missing-book', method: 'GUIJI_CHAPTER_SUBSTRING_MATCH'),
      ],
      requestId: 'combined',
    );

    expect(ranked.status, RankedEvidenceSetStatus.noUsableEvidence);
    expect(ranked.orderedEvidenceIds, isEmpty);
    expect(ranked.decisions.map((item) => item.reasonCode), [
      'UNSUPPORTED_RETRIEVAL_METHOD',
      'GUIJI_BOOK_ID_MISSING',
    ]);
    expect(ranked.diagnostics, contains('UNSUPPORTED_RETRIEVAL_METHOD_DROPPED'));
  });

  test('rejects duplicate evidence identities', () {
    final duplicate = _candidate(id: 'same', method: 'CLASSIC_SUBSTRING_INDEX');
    expect(
      () => SourceAwareLegacyEvidenceRanker.rank(
        [duplicate, duplicate],
        requestId: 'combined',
      ),
      throwsStateError,
    );
  });
}
