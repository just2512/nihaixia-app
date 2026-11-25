import '../models/ai_evidence.dart';
import '../models/evidence_ranking_decision.dart';

/// Applies source-specific legacy limits to one combined candidate sequence.
///
/// This is a deterministic compatibility policy, not semantic relevance
/// ranking. It never scores, promotes source verification, or applies a
/// character/token budget. Unknown retrieval methods fail closed.
class SourceAwareLegacyEvidenceRanker {
  static const String strategyId = 'LEGACY_SOURCE_ORDER_WITH_PER_SOURCE_LIMITS';
  static const String strategyVersion = '1';

  static const int classicIndexLimit = 4;
  static const int medicalCaseLimit = 2;
  static const int gujiChapterLimitPerBook = 2;

  static RankedEvidenceSet rank(
    List<CandidateEvidence> candidates, {
    required String requestId,
  }) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }

    final seenEvidenceIds = <String>{};
    final keptByGroup = <String, int>{};
    final decisions = <EvidenceRankingDecision>[];
    var retainedOrder = 0;
    var hasUnsupportedMethod = false;

    for (final candidate in candidates) {
      final evidenceId = candidate.evidenceId;
      if (evidenceId.trim().isEmpty) {
        throw StateError('Candidate evidenceId must not be empty');
      }
      if (!seenEvidenceIds.add(evidenceId)) {
        throw StateError('Duplicate candidate evidenceId: $evidenceId');
      }

      final policy = _policyFor(candidate);
      if (policy == null) {
        hasUnsupportedMethod = true;
        decisions.add(
          EvidenceRankingDecision(
            evidenceId: evidenceId,
            disposition: EvidenceDecisionDisposition.drop,
            reasonCode: candidate.retrievalMethod ==
                    'GUIJI_CHAPTER_SUBSTRING_MATCH'
                ? 'GUIJI_BOOK_ID_MISSING'
                : 'UNSUPPORTED_RETRIEVAL_METHOD',
            reason: candidate.retrievalMethod ==
                    'GUIJI_CHAPTER_SUBSTRING_MATCH'
                ? 'Excluded because the Guji candidate has no stable bookId.'
                : 'Excluded because no legacy source policy is registered for '
                    'this retrieval method.',
          ),
        );
        continue;
      }

      final used = keptByGroup[policy.groupKey] ?? 0;
      if (used < policy.limit) {
        keptByGroup[policy.groupKey] = used + 1;
        decisions.add(
          EvidenceRankingDecision(
            evidenceId: evidenceId,
            disposition: EvidenceDecisionDisposition.keep,
            reasonCode: policy.keepReasonCode,
            reason: policy.keepReason,
            orderIndex: retainedOrder++,
          ),
        );
      } else {
        decisions.add(
          EvidenceRankingDecision(
            evidenceId: evidenceId,
            disposition: EvidenceDecisionDisposition.drop,
            reasonCode: policy.dropReasonCode,
            reason: policy.dropReason,
          ),
        );
      }
    }

    final orderedEvidenceIds = decisions
        .where(
          (decision) =>
              decision.disposition == EvidenceDecisionDisposition.keep,
        )
        .map((decision) => decision.evidenceId)
        .toList(growable: false);

    return RankedEvidenceSet(
      requestId: requestId,
      strategyId: strategyId,
      strategyVersion: strategyVersion,
      decisions: decisions,
      orderedEvidenceIds: orderedEvidenceIds,
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
        'LEGACY_SOURCE_SPECIFIC_COUNT_LIMITS',
        if (hasUnsupportedMethod) 'UNSUPPORTED_RETRIEVAL_METHOD_DROPPED',
        'BUDGET_NOT_APPLIED',
      ],
    );
  }

  static _SourceLimitPolicy? _policyFor(CandidateEvidence candidate) {
    switch (candidate.retrievalMethod) {
      case 'CLASSIC_SUBSTRING_INDEX':
        return const _SourceLimitPolicy(
          groupKey: 'classic-index',
          limit: classicIndexLimit,
          keepReasonCode: 'LEGACY_CLASSIC_INDEX_ORDER_WITHIN_LIMIT',
          keepReason: 'Preserved the existing classic-index query/hit order.',
          dropReasonCode: 'LEGACY_CLASSIC_INDEX_FOUR_HIT_LIMIT',
          dropReason: 'Excluded by the existing four-hit classic-index limit.',
        );
      case 'MEDICAL_CASE_NORMALIZED_TEXT_MATCH':
        return const _SourceLimitPolicy(
          groupKey: 'medical-case',
          limit: medicalCaseLimit,
          keepReasonCode: 'LEGACY_MEDICAL_CASE_SEQUENCE_WITHIN_LIMIT',
          keepReason: 'Preserved the existing medical-case sequence.',
          dropReasonCode: 'LEGACY_MEDICAL_CASE_TWO_RESULT_LIMIT',
          dropReason: 'Excluded by the existing two-case result limit.',
        );
      case 'GUIJI_CHAPTER_SUBSTRING_MATCH':
        final bookId = candidate.bookId?.trim() ?? '';
        if (bookId.isEmpty) return null;
        return _SourceLimitPolicy(
          groupKey: 'guji:$bookId',
          limit: gujiChapterLimitPerBook,
          keepReasonCode: 'LEGACY_GUIJI_CHAPTER_SEQUENCE_WITHIN_BOOK',
          keepReason: 'Preserved the existing chapter sequence and two-chapter '
              'per-book limit.',
          dropReasonCode: 'LEGACY_GUIJI_TWO_CHAPTER_LIMIT',
          dropReason: 'Excluded by the existing two-chapter per-book limit.',
        );
      default:
        return null;
    }
  }
}

class _SourceLimitPolicy {
  const _SourceLimitPolicy({
    required this.groupKey,
    required this.limit,
    required this.keepReasonCode,
    required this.keepReason,
    required this.dropReasonCode,
    required this.dropReason,
  });

  final String groupKey;
  final int limit;
  final String keepReasonCode;
  final String keepReason;
  final String dropReasonCode;
  final String dropReason;
}
