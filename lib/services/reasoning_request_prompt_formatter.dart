import 'dart:convert';

import '../models/reasoning_request.dart';
import 'session_state_snapshot_prompt_formatter.dart';

/// Renders only the supplemental, request-scoped metadata for Native text input.
///
/// The original [ReasoningRequest.userText] continues through the existing
/// Native "text" argument unchanged. Retrieved evidence bodies continue
/// through the existing bounded knowledge-context argument; this formatter
/// sends identity pointers and App execution results, not duplicate source text.
class ReasoningRequestPromptFormatter {
  static const String header = '【App 本轮推理请求元数据 v1】';
  /// UTF-16 code-unit bound for supplemental metadata only; not a model-token budget.
  static const int maxSupplementalContextCharacters = 24000;

  static String formatSupplementalContext(
    ReasoningRequest request, {
    bool includeSessionState = true,
  }) {
    final sessionStateContext = !includeSessionState
        ? null
        : request.sessionState == null
            ? '【App 本会话结构化记忆快照】\nstatus=UNKNOWN\n结构化事实：未提供。\n来源引用：未提供。'
            : SessionStateSnapshotPromptFormatter.format(
                request.sessionState!,
                expectedSessionId: request.sessionId,
              );

    final envelope = <String, Object?>{
      'schemaVersion': 1,
      'requestId': request.requestId,
      'sessionId': request.sessionId,
      'mode': request.mode,
      'responseSchemaVersion': request.responseSchemaVersion,
      'responseContract': {
        'schemaVersion': request.responseSchemaVersion,
        'requiredFields': const [
          'schemaVersion', 'requestId', 'responseKind', 'status', 'segments',
          'referencedEvidenceIds', 'unknowns', 'conflicts', 'omittedEvidenceIds',
        ],
        'responseKinds': const [
          'ANSWER', 'CLARIFICATION', 'ACTION_PROPOSAL', 'REFUSAL', 'INSUFFICIENT_EVIDENCE',
        ],
        'modelStatuses': const ['COMPLETED', 'INSUFFICIENT_EVIDENCE'],
        'rules': const [
          'Return exactly one JSON object; do not wrap it in Markdown fences.',
          'requestId must exactly equal this requestId.',
          'Every referencedEvidenceId must be present in rankedEvidence.',
          'knownEvidenceIds may validate omissions but must never be cited unless also ranked.',
          'ACTION_PROPOSAL is an untrusted proposal; it is not authorization or execution.',
          'Do not claim SUCCEEDED for any action unless the App supplied a SUCCEEDED execution result.',
          'Use INSUFFICIENT_EVIDENCE when the supplied evidence cannot support the answer.',
        ],
      },
      if (includeSessionState) 'sessionStateContext': sessionStateContext,
      if (!includeSessionState)
        'sessionStateProvidedSeparately': request.sessionState != null,
      'rankedEvidence': request.rankedEvidence.map((item) => item.toMap()).toList(),
      'knownEvidenceIds': request.knownEvidenceIds,
      'executionResults':
          request.executionResults.map((item) => item.toMap()).toList(),
      'boundaries': const [
        'userText is supplied separately as the original Native text input; do not rewrite or replace it.',
        'rankedEvidence contains only evidence IDs whose complete blocks are present in this request context.',
        'knownEvidenceIds may include dropped candidates; they are not allowed citations.',
        'sourceId is an App lookup pointer, not a verification or authority claim.',
        'executionResults are App-projected results; preserve UNKNOWN and never claim an unverified action succeeded.',
        'This contract does not grant permission or authorize tool execution.',
      ],
    };
    final formatted = [header, jsonEncode(envelope)].join('\n');
    if (formatted.length > maxSupplementalContextCharacters) {
      throw StateError('REASONING_REQUEST_SUPPLEMENTAL_CONTEXT_EXCEEDS_CHARACTER_BOUND');
    }
    return formatted;
  }
}
