/// One auditable keep/drop decision made by an evidence-ranking strategy.
///
/// The legacy-order strategy deliberately has no numeric score: orderIndex
/// records only the historical query/hit sequence, not factual confidence or
/// source authority.
enum EvidenceDecisionDisposition { keep, drop }

class EvidenceRankingDecision {
  const EvidenceRankingDecision({
    required this.evidenceId,
    required this.disposition,
    required this.reasonCode,
    required this.reason,
    this.orderIndex,
  });

  final String evidenceId;
  final EvidenceDecisionDisposition disposition;
  final String reasonCode;
  final String reason;

  /// Zero-based position within the retained evidence set; DROP has no index.
  final int? orderIndex;
}

enum EvidenceBudgetUnit { characters, tokens, unknown }

enum RankedEvidenceSetStatus {
  ranked,
  noUsableEvidence,
  budgetTruncated,
  failed,
}

/// Honest budget accounting for a ranking result.
///
/// A null limit/used value with [applied] false means the strategy did not
/// enforce a character/token budget. It must not be inferred from the legacy
/// four-evidence compatibility limit.
class EvidenceBudgetSnapshot {
  EvidenceBudgetSnapshot({
    required this.unit,
    required this.limit,
    required this.used,
    required this.applied,
    required List<String> omittedEvidenceIds,
    required List<String> truncatedEvidenceIds,
  })  : omittedEvidenceIds = List.unmodifiable(omittedEvidenceIds),
        truncatedEvidenceIds = List.unmodifiable(truncatedEvidenceIds);

  final EvidenceBudgetUnit unit;
  final int? limit;
  final int? used;
  final bool applied;
  final List<String> omittedEvidenceIds;
  final List<String> truncatedEvidenceIds;
}

/// Auditable output contract between candidate recall and model-input assembly.
class RankedEvidenceSet {
  RankedEvidenceSet({
    required this.requestId,
    required this.strategyId,
    required this.strategyVersion,
    required List<EvidenceRankingDecision> decisions,
    required List<String> orderedEvidenceIds,
    required this.budget,
    required this.status,
    required List<String> diagnostics,
  })  : decisions = List.unmodifiable(decisions),
        orderedEvidenceIds = List.unmodifiable(orderedEvidenceIds),
        diagnostics = List.unmodifiable(diagnostics);

  final String requestId;
  final String strategyId;
  final String strategyVersion;
  final List<EvidenceRankingDecision> decisions;
  final List<String> orderedEvidenceIds;
  final EvidenceBudgetSnapshot budget;
  final RankedEvidenceSetStatus status;
  final List<String> diagnostics;
}
