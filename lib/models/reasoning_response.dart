/// Strict, immutable response contract for the local E4B reasoning layer.
///
/// This DTO is deliberately separate from Native Conversation and from the
/// deterministic business-execution pipeline. Decoding a proposal never
/// executes it; the registered capability gate remains authoritative.
enum ReasoningResponseKind {
  answer,
  clarification,
  actionProposal,
  refusal,
  insufficientEvidence,
}

enum ReasoningResponseStatus {
  completed,
  empty,
  parseFailed,
  insufficientEvidence,
  unknown,
}

class BusinessActionProposal {
  BusinessActionProposal({
    required this.proposalId,
    required this.capabilityId,
    required Map<String, String> arguments,
  }) : arguments = Map.unmodifiable(arguments);

  final String proposalId;
  final String capabilityId;
  final Map<String, String> arguments;
}

/// A model response after structural and request-local reference validation.
///
/// [referencedEvidenceIds] must refer only to evidence actually supplied to
/// the current reasoning request. Source truth and local source resolution are
/// still owned by the data layer and are not established by this response.
class ReasoningResponse {
  ReasoningResponse({
    required this.requestId,
    required this.responseKind,
    required this.status,
    required List<String> segments,
    required List<String> referencedEvidenceIds,
    required List<String> unknowns,
    required List<String> conflicts,
    required List<String> omittedEvidenceIds,
    this.actionProposal,
  })  : segments = List.unmodifiable(segments),
        referencedEvidenceIds = List.unmodifiable(referencedEvidenceIds),
        unknowns = List.unmodifiable(unknowns),
        conflicts = List.unmodifiable(conflicts),
        omittedEvidenceIds = List.unmodifiable(omittedEvidenceIds);

  final String requestId;
  final ReasoningResponseKind responseKind;
  final ReasoningResponseStatus status;
  final List<String> segments;
  final List<String> referencedEvidenceIds;
  final List<String> unknowns;
  final List<String> conflicts;
  final List<String> omittedEvidenceIds;
  final BusinessActionProposal? actionProposal;
}

/// Result of decoding an untrusted model payload.
///
/// EMPTY / PARSE_FAILED / UNKNOWN are produced by application code, never
/// accepted as model-declared success states.
class ReasoningResponseDecodeResult {
  ReasoningResponseDecodeResult({
    required this.status,
    required List<String> diagnostics,
    this.response,
  }) : diagnostics = List.unmodifiable(diagnostics);

  final ReasoningResponseStatus status;
  final ReasoningResponse? response;
  final List<String> diagnostics;

  bool get isUsable =>
      response != null &&
      (status == ReasoningResponseStatus.completed ||
          status == ReasoningResponseStatus.insufficientEvidence);
}
