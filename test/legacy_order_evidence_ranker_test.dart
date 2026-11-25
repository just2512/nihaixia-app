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

    final decisions = LegacyOrderEvidenceRanker.rank(candidates);

    expect(decisions, hasLength(candidates.length));
    expect(decisions.map((item) => item.evidenceId).toSet(),
        candidates.map((item) => item.evidenceId).toSet());
    expect(decisions.map((item) => item.reasonCode), everyElement(isNotEmpty));
  });

  test('keeps the first four in original order and drops the remainder', () {
    final candidates = List.generate(7, (index) => _candidate('e$index'));

    final decisions = LegacyOrderEvidenceRanker.rank(candidates);
    final kept = decisions
        .where((item) => item.disposition == EvidenceDecisionDisposition.keep)
        .toList()
      ..sort((left, right) => left.orderIndex!.compareTo(right.orderIndex!));
    final dropped = decisions
        .where((item) => item.disposition == EvidenceDecisionDisposition.drop);

    expect(kept.map((item) => item.evidenceId), ['e0', 'e1', 'e2', 'e3']);
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
    final decisions = LegacyOrderEvidenceRanker.rank(
      [_candidate('e0')],
      maxKeptEvidence: 0,
    );
    expect(decisions.single.disposition, EvidenceDecisionDisposition.drop);
    expect(
      () => LegacyOrderEvidenceRanker.rank(
        [_candidate('e0')],
        maxKeptEvidence: -1,
      ),
      throwsArgumentError,
    );
  });

  test('rejects duplicate or empty evidence identities', () {
    expect(
      () => LegacyOrderEvidenceRanker.rank([
        _candidate('duplicate'),
        _candidate('duplicate'),
      ]),
      throwsStateError,
    );
    expect(
      () => LegacyOrderEvidenceRanker.rank([_candidate('  ')]),
      throwsStateError,
    );
  });
}
