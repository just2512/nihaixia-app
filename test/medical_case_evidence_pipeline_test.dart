import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/models/evidence_ranking_decision.dart';
import 'package:nihaisha_app/services/legacy_order_evidence_ranker.dart';
import 'package:nihaisha_app/services/medical_case_evidence_pipeline.dart';

MedicalCase _case(
  int sequence, {
  String diagnosis = '',
  String mechanism = '',
  String formula = '',
  String result = '',
}) {
  return MedicalCase(
    seq: sequence,
    diagnosis: diagnosis,
    mechanism: mechanism,
    formula: formula,
    result: result,
  );
}

void main() {
  test('retrieves matching local case records once and preserves case order', () {
    final cases = [
      _case(18, diagnosis: '头痛', formula: '桂枝汤'),
      _case(7, diagnosis: '眩晕', mechanism: '肝阳上亢'),
      _case(23, result: '桂枝汤后症状改善'),
      _case(31, diagnosis: '无关条目'),
    ];

    final batch = MedicalCaseEvidencePipeline.retrieveCandidates(
      requestId: 'request-1:medical-cases',
      originalQuery: '桂枝汤 头痛',
      terms: const ['桂枝汤', '头痛', '肝阳'],
      cases: cases,
    );

    expect(batch.status, CandidateEvidenceBatchStatus.retrieved);
    expect(
      batch.candidates.map((item) => item.sourceId),
      ['medical_case:18', 'medical_case:7', 'medical_case:23'],
    );
    expect(
      batch.candidates.map((item) => item.queryId),
      ['medical-q1', 'medical-q3', 'medical-q1'],
    );
    expect(batch.candidates.map((item) => item.evidenceId).toSet(), hasLength(3));
    expect(
      batch.candidates.every((item) => item.origin == CandidateEvidenceOrigin.appData),
      isTrue,
    );
    expect(
      batch.candidates.every((item) => item.hasLocalBacklink),
      isTrue,
    );
    expect(batch.candidates.first.localBacklink, 'medical_case:18');
    expect(batch.candidates.first.excerpt, contains('诊断：头痛'));
    expect(batch.candidates.first.excerpt, contains('方剂：桂枝汤'));
  });

  test('selection retains the historical two-case limit without scoring', () {
    final batch = MedicalCaseEvidencePipeline.retrieveCandidates(
      requestId: 'request-2',
      originalQuery: '桂枝汤',
      terms: const ['桂枝汤'],
      cases: [
        _case(1, formula: '桂枝汤'),
        _case(2, formula: '桂枝汤'),
        _case(3, formula: '桂枝汤'),
      ],
    );

    final ranked = LegacyOrderEvidenceRanker.rank(
      batch.candidates,
      requestId: batch.requestId,
      maxKeptEvidence: 2,
      keepReasonCode: 'LEGACY_MEDICAL_CASE_SEQUENCE_WITHIN_LIMIT',
      keepReason: 'Preserved the existing medical-case order.',
      dropReasonCode: 'LEGACY_MEDICAL_CASE_TWO_RESULT_LIMIT',
      dropReason: 'Excluded by the existing two-case result limit.',
    );

    expect(
      ranked.orderedEvidenceIds,
      batch.candidates.take(2).map((item) => item.evidenceId).toList(),
    );
    expect(
      ranked.decisions.map((item) => item.disposition),
      [
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.keep,
        EvidenceDecisionDisposition.drop,
      ],
    );
    expect(
      ranked.decisions.last.reasonCode,
      'LEGACY_MEDICAL_CASE_TWO_RESULT_LIMIT',
    );
    expect(ranked.budget.unit, EvidenceBudgetUnit.unknown);
    expect(ranked.budget.applied, isFalse);
    expect(ranked.budget.limit, isNull);
    expect(ranked.budget.used, isNull);
  });

  test('returns an empty batch when no local case matches', () {
    final batch = MedicalCaseEvidencePipeline.retrieveCandidates(
      requestId: 'request-3',
      originalQuery: '不存在的内容',
      terms: const ['不存在的内容'],
      cases: [_case(1, diagnosis: '其他')],
    );
    expect(batch.status, CandidateEvidenceBatchStatus.missing);
    expect(batch.candidates, isEmpty);
    expect(batch.diagnostics, contains('MEDICAL_CASE_NO_MATCH'));
  });

  test('rejects an empty request id', () {
    expect(
      () => MedicalCaseEvidencePipeline.retrieveCandidates(
        requestId: ' ',
        originalQuery: '桂枝汤',
        terms: const ['桂枝汤'],
        cases: const [],
      ),
      throwsArgumentError,
    );
  });
}
