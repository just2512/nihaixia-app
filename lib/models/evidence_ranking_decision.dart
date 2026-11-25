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
