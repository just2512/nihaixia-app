import '../models/reasoning_request.dart';
import '../models/reasoning_response.dart';
import '../models/session_state_snapshot.dart';
import 'assistant_knowledge_context.dart';
import 'reasoning_action_proposal_gate.dart';
import 'reasoning_knowledge_answer_adapter.dart';
import 'reasoning_response_codec.dart';

/// Normalized output from a structured tool-mode reasoning turn.
///
/// A proposal produces only a confirmation preview. A natural-language answer
/// still goes through the knowledge answer adapter so evidence references are
/// resolved against the App-side source map.
class ReasoningActionProposalTurnResult {
  const ReasoningActionProposalTurnResult({
    required this.decodeResult,
    this.answerResult,
    this.gateResult,
  });

  final ReasoningResponseDecodeResult decodeResult;
  final ReasoningKnowledgeAnswerResult? answerResult;
  final ReasoningActionProposalGateResult? gateResult;

  bool get isUsableAnswer => answerResult?.isUsable == true;
  bool get requiresConfirmation => gateResult?.requiresConfirmation == true;
  bool get isRejected => !isUsableAnswer && !requiresConfirmation;
}

/// Builds and validates Core-4 tool-mode reasoning requests.
///
/// Capability scope is copied from App-owned request construction. This
/// adapter cannot infer capabilities from model text, authorize a user, or run
/// a Headless executor.
class ReasoningActionProposalAdapter {
  const ReasoningActionProposalAdapter._();

  static ReasoningRequest createRequest({
    required String requestId,
    required int sessionId,
    required String userText,
    required SessionStateSnapshot sessionState,
    required AssistantKnowledgeContextResult knowledge,
    required Set<String> requestCapabilityAllowlist,
    List<ReasoningExecutionResult> executionResults = const [],
  }) {
    if (requestCapabilityAllowlist.isEmpty) {
      throw ArgumentError('REASONING_TOOL_REQUEST_CAPABILITY_ALLOWLIST_EMPTY');
    }
    return ReasoningKnowledgeAnswerAdapter.createRequest(
      requestId: requestId,
      sessionId: sessionId,
      userText: userText,
      mode: 'tools',
      sessionState: sessionState,
      knowledge: knowledge,
      allowedCapabilityIds: requestCapabilityAllowlist.toList()..sort(),
      executionResults: executionResults,
    );
  }

  static ReasoningActionProposalTurnResult decodeAndPrepare({
    required String raw,
    required ReasoningRequest request,
    required AssistantKnowledgeContextResult knowledge,
  }) {
    if (request.mode != 'tools' || request.allowedCapabilityIds.isEmpty) {
      return _failure('REASONING_TOOL_REQUEST_CAPABILITY_SCOPE_MISSING');
    }

    final decoded = ReasoningResponseCodec.decode(
      raw: raw,
      expectedRequestId: request.requestId,
      rankedEvidenceIds: request.rankedEvidenceIds.toSet(),
      knownEvidenceIds: request.knownEvidenceIds.toSet(),
      allowedCapabilityIds: request.allowedCapabilityIds.toSet(),
    );
    final response = decoded.response;
    if (!decoded.isUsable || response == null) {
      return ReasoningActionProposalTurnResult(decodeResult: decoded);
    }

    if (response.responseKind == ReasoningResponseKind.actionProposal) {
      final gate = ReasoningActionProposalGate.prepareForConfirmation(
        response: response,
        expectedRequestId: request.requestId,
        requestCapabilityAllowlist: request.allowedCapabilityIds.toSet(),
      );
      if (!gate.requiresConfirmation || gate.preview == null || gate.plan != null) {
        return ReasoningActionProposalTurnResult(
          decodeResult: ReasoningResponseDecodeResult(
            status: ReasoningResponseStatus.unknown,
            diagnostics: gate.errors.isEmpty
                ? const ['REASONING_ACTION_PROPOSAL_GATE_REJECTED']
                : gate.errors,
          ),
          gateResult: gate,
        );
      }
      return ReasoningActionProposalTurnResult(
        decodeResult: decoded,
        gateResult: gate,
      );
    }

    final answer = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
      raw: raw,
      request: request,
      knowledge: knowledge,
    );
    return ReasoningActionProposalTurnResult(
      decodeResult: answer.decodeResult,
      answerResult: answer,
    );
  }

  static ReasoningActionProposalGateResult authorizeAfterConfirmation({
    required ReasoningActionProposalPreview preview,
    required ReasoningRequest request,
    required bool confirmedByUser,
  }) {
    final validRequestScope =
        request.mode == 'tools' && request.requestId == preview.requestId;
    return ReasoningActionProposalGate.authorizeAfterConfirmation(
      preview: preview,
      expectedRequestId: validRequestScope ? request.requestId : '',
      requestCapabilityAllowlist: validRequestScope
          ? request.allowedCapabilityIds.toSet()
          : const <String>{},
      confirmedByUser: confirmedByUser,
    );
  }

  static ReasoningActionProposalTurnResult _failure(String code) =>
      ReasoningActionProposalTurnResult(
        decodeResult: ReasoningResponseDecodeResult(
          status: ReasoningResponseStatus.unknown,
          diagnostics: [code],
        ),
      );
}
