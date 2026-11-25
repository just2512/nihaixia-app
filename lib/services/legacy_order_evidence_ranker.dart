import '../models/ai_evidence.dart';
import '../models/evidence_ranking_decision.dart';
import 'classic_evidence_pipeline.dart';

/// First deterministic evidence-selection slice.
///
/// This is intentionally a compatibility strategy, not semantic ranking:
/// preserve the exact sequence already protected by the retrieval golden
/// snapshots and explicitly account for candidates excluded by the four-hit
/// legacy context limit.
class LegacyOrderEvidenceRanker {
  static const String strategyId = 'LEGACY_QUERY_ORDER';
  static const String strategyVersion = '1';

  static RankedEvidenceSet rank(
    List<CandidateEvidence> candidates, {
    required String requestId,
    int maxKeptEvidence = ClassicEvidencePipeline.legacyContextHitLimit,
    String keepReasonCode = 'LEGACY_QUERY_ORDER_WITHIN_LIMIT',
    String keepReason = 'Preserved the existing classic-query and hit order.',
    String dropReasonCode = 'LEGACY_CONTEXT_HIT_LIMIT',
    String dropReason = 'Excluded by the existing four-hit context limit.',
  }) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }
    if (maxKeptEvidence < 0) {
      throw ArgumentError.value(
        maxKeptEvidence,
        'maxKeptEvidence',
        'Must not be negative',
      );
    }

    final seenIds = <String>{};
    final decisions = <EvidenceRankingDecision>[];
    var retainedOrder = 0;

    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final evidenceId = candidate.evidenceId;
      if (evidenceId.trim().isEmpty) {
        throw StateError('Candidate evidenceId must not be empty');
      }
      if (!seenIds.add(evidenceId)) {
        throw StateError('Duplicate candidate evidenceId: $evidenceId');
      }

      if (retainedOrder < maxKeptEvidence) {
        decisions.add(
          EvidenceRankingDecision(
            evidenceId: evidenceId,
            disposition: EvidenceDecisionDisposition.keep,
            reasonCode: keepReasonCode,
            reason: keepReason,
            orderIndex: retainedOrder++,
          ),
        );
      } else {
        decisions.add(
          EvidenceRankingDecision(
            evidenceId: evidenceId,
            disposition: EvidenceDecisionDisposition.drop,
            reasonCode: dropReasonCode,
            reason: dropReason,
          ),
        );
      }
    }

    final orderedEvidenceIds = decisions
        .where((decision) => decision.disposition == EvidenceDecisionDisposition.keep)
        .toList()
      ..sort((left, right) => left.orderIndex!.compareTo(right.orderIndex!));

    return RankedEvidenceSet(
      requestId: requestId,
      strategyId: strategyId,
      strategyVersion: strategyVersion,
      decisions: decisions,
      orderedEvidenceIds: [
        for (final decision in orderedEvidenceIds) decision.evidenceId,
      ],
      budget: EvidenceBudgetSnapshot(
        unit: EvidenceBudgetUnit.unknown,
        limit: null,
        used: null,
        applied: false,
        omittedEvidenceIds: const [],
        truncatedEvidenceIds: const [],
      ),
      status: orderedEvidenceIds.isEmpty
          ? RankedEvidenceSetStatus.noUsableEvidence
          : RankedEvidenceSetStatus.ranked,
      diagnostics: [
        'LEGACY_CONTEXT_COUNT_LIMIT:$maxKeptEvidence',
        'BUDGET_NOT_APPLIED_IN_LEGACY_COMPATIBILITY_SLICE',
      ],
    );
  }
}
