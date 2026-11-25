import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/models/evidence_ranking_decision.dart';
import 'package:nihaisha_app/services/legacy_order_evidence_ranker.dart';

CandidateEvidence _candidate(String evidenceId) {
  return CandidateEvidence(
    evidenceId: evidenceId,
    sourceId: 'classic:$evidenceId',
    sourceVersion: 'UNKNOWN',
    origin: CandidateEvidenceOrigin.system,
    materialKind: 'classic_text',
    verificationStatus: 'UNKNOWN',
    title: evidenceId,
    locator: 'MISSING',
    locatorStatus: 'MISSING',
    excerpt: 'excerpt:$evidenceId',
    queryId: 'q1',
    retrievalMethod: 'CLASSIC_SUBSTRING_INDEX',
    matchBasis: 'UNKNOWN',
    completeness: CandidateEvidenceCompleteness.unknown,
    sourceKey: 'shanghan',
    sourceLabel: '伤寒论讲稿',
    localBacklink: 'MISSING',
    hasLocalBacklink: false,
  );
}

void main() {
  test('emits an explicit decision for every candidate', () {
    final candidates = List.generate(7, (index) => _candidate('e$index'));

    final ranked = LegacyOrderEvidenceRanker.rank(candidates, requestId: 'test-request');
    final decisions = ranked.decisions;

    expect(ranked.requestId, 'test-request');
    expect(ranked.strategyId, LegacyOrderEvidenceRanker.strategyId);
    expect(ranked.strategyVersion, LegacyOrderEvidenceRanker.strategyVersion);
    expect(ranked.status, RankedEvidenceSetStatus.ranked);
    expect(ranked.budget.unit, EvidenceBudgetUnit.unknown);
    expect(ranked.budget.applied, isFalse);
    expect(ranked.budget.limit, isNull);
    expect(ranked.budget.used, isNull);
    expect(ranked.diagnostics,
        contains('BUDGET_NOT_APPLIED_IN_LEGACY_COMPATIBILITY_SLICE'));
    expect(decisions, hasLength(candidates.length));
    expect(decisions.map((item) => item.evidenceId).toSet(),
        candidates.map((item) => item.evidenceId).toSet());
    expect(decisions.map((item) => item.reasonCode), everyElement(isNotEmpty));
  });

  test('keeps the first four in original order and drops the remainder', () {
    final candidates = List.generate(7, (index) => _candidate('e$index'));

    final ranked = LegacyOrderEvidenceRanker.rank(candidates, requestId: 'test-request');
    final decisions = ranked.decisions;
    final kept = decisions
        .where((item) => item.disposition == EvidenceDecisionDisposition.keep)
        .toList()
      ..sort((left, right) => left.orderIndex!.compareTo(right.orderIndex!));
    final dropped = decisions
        .where((item) => item.disposition == EvidenceDecisionDisposition.drop);

    expect(kept.map((item) => item.evidenceId), ['e0', 'e1', 'e2', 'e3']);
    expect(ranked.orderedEvidenceIds, ['e0', 'e1', 'e2', 'e3']);
    expect(ranked.budget.omittedEvidenceIds, isEmpty);
    expect(ranked.budget.truncatedEvidenceIds, isEmpty);
    expect(kept.map((item) => item.orderIndex), [0, 1, 2, 3]);
    expect(
      kept.every((item) =>
          item.reasonCode == 'LEGACY_QUERY_ORDER_WITHIN_LIMIT'),
      isTrue,
    );
    expect(dropped.map((item) => item.evidenceId), ['e4', 'e5', 'e6']);
    expect(dropped.every((item) => item.orderIndex == null), isTrue);
    expect(
      dropped.every((item) => item.reasonCode == 'LEGACY_CONTEXT_HIT_LIMIT'),
      isTrue,
    );
  });

  test('allows an explicit zero keep budget and rejects a negative limit', () {
    final ranked = LegacyOrderEvidenceRanker.rank(
      [_candidate('e0')],
      requestId: 'test-request',
      maxKeptEvidence: 0,
    );
    expect(ranked.decisions.single.disposition, EvidenceDecisionDisposition.drop);
    expect(ranked.status, RankedEvidenceSetStatus.noUsableEvidence);
    expect(
      () => LegacyOrderEvidenceRanker.rank(
        [_candidate('e0')],
        requestId: 'test-request',
        maxKeptEvidence: -1,
      ),
      throwsArgumentError,
    );
  });

  test('preserves evidence IDs as opaque unnormalized values', () {
    final decision = LegacyOrderEvidenceRanker.rank(
      [_candidate(' evidence-id ')],
      requestId: 'test-request',
    ).decisions.single;
    expect(decision.evidenceId, ' evidence-id ');
  });

  test('rejects duplicate or empty evidence identities', () {
    expect(
      () => LegacyOrderEvidenceRanker.rank(
        [_candidate('duplicate'), _candidate('duplicate')],
        requestId: 'test-request',
      ),
      throwsStateError,
    );
    expect(
      () => LegacyOrderEvidenceRanker.rank([_candidate('  ')], requestId: 'test-request'),
      throwsStateError,
    );
  });
}
