import 'dart:convert';

import '../models/reasoning_request.dart';
import '../models/session_state_snapshot.dart';

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

  static String formatSupplementalContext(ReasoningRequest request) {
    // SessionStateSnapshot content already travels through the dedicated
    // Native session_state_context field, where MainActivity validates the
    // active SQLite conversation owner. Keep only its bounded metadata here
    // to avoid sending the same memory facts twice in one model input.
    final sessionState = request.sessionState;
    final sessionStateMetadata = <String, Object?>{
      'sessionId': request.sessionId,
      'revision': sessionState?.revision ?? 'UNKNOWN',
      'status': switch (sessionState?.status) {
        SessionStateStatus.restored => 'RESTORED',
        SessionStateStatus.partial => 'PARTIAL',
        SessionStateStatus.sessionMismatch => 'SESSION_MISMATCH',
        SessionStateStatus.unknown || null => 'UNKNOWN',
      },
      'contentTransport': 'NATIVE_SESSION_STATE_CONTEXT',
    };

    final envelope = <String, Object?>{
      'schemaVersion': 1,
      'requestId': request.requestId,
      'sessionId': request.sessionId,
      'mode': request.mode,
      'responseSchemaVersion': request.responseSchemaVersion,
      if (request.attachmentType != null) 'attachment': {
        'type': request.attachmentType!.name,
        'userTextOrigin': request.attachmentPromptGenerated ? 'APP_ATTACHMENT_PROMPT' : 'USER_ORIGINAL',
        'responseShape': request.attachmentType == ReasoningAttachmentType.image
            ? {'type': 'image', 'observations': ['直接可观察到的描述']}
            : {'type': 'audio', 'transcriptDraft': '完整转写草稿'},
      },
      'responseContract': {
        'schemaVersion': request.responseSchemaVersion,
        'requiredFields': [
          'schemaVersion', 'requestId', 'responseKind', 'status', 'segments',
          'referencedEvidenceIds', 'unknowns', 'conflicts', 'omittedEvidenceIds',
          if (request.attachmentType != null) 'attachmentResult',
        ],
        'responseKinds': const [
          'ANSWER', 'CLARIFICATION', 'ACTION_PROPOSAL', 'REFUSAL', 'INSUFFICIENT_EVIDENCE',
        ],
        'modelStatuses': const ['COMPLETED', 'INSUFFICIENT_EVIDENCE'],
        'attachmentResultRules': request.attachmentType == ReasoningAttachmentType.image
            ? 'Required: image observations must contain directly visible details; do not infer a diagnosis.'
            : request.attachmentType == ReasoningAttachmentType.audio
                ? 'Required: audio transcriptDraft must be non-empty and remains an unconfirmed draft, never user fact.'
                : null,
        'rules': const [
          'Return exactly one JSON object; do not wrap it in Markdown fences.',
          'requestId must exactly equal this requestId.',
          'Every referencedEvidenceId must be present in rankedEvidence.',
          'knownEvidenceIds may validate omissions but must never be cited unless also ranked.',
          'ACTION_PROPOSAL is an untrusted proposal; it is not authorization or execution.',
          'If actionCapabilityAllowlist is empty, never return ACTION_PROPOSAL.',
          'A proposal may name only one capability in actionCapabilityAllowlist; the App still requires explicit confirmation.',
          'Do not claim SUCCEEDED for any action unless the App supplied a SUCCEEDED execution result.',
          'Use INSUFFICIENT_EVIDENCE when the supplied evidence cannot support the answer.',
        ],
      },
      'sessionStateMetadata': sessionStateMetadata,
      // The model receives evidence IDs only. App source IDs remain in the
      // adapter's private mapping and are never exposed as natural-language or
      // prompt-visible provenance.
      'rankedEvidence': request.rankedEvidence
          .map((item) => {'evidenceId': item.evidenceId})
          .toList(),
      'knownEvidenceIds': request.knownEvidenceIds,
      'actionCapabilityAllowlist': request.allowedCapabilityIds,
      // Execution values and status are model-visible; provenance and
      // invocation identity remain App-owned metadata and never enter prompt.
      'executionResults': request.executionResults
          .map((item) => <String, Object?>{
                'capabilityId': item.capabilityId,
                'status': switch (item.status) {
                  ReasoningExecutionStatus.notStarted => 'NOT_STARTED',
                  ReasoningExecutionStatus.succeeded => 'SUCCEEDED',
                  ReasoningExecutionStatus.failed => 'FAILED',
                  ReasoningExecutionStatus.unknown => 'UNKNOWN',
                },
                'actualArguments': item.actualArguments,
                'resultValues': item.resultValues,
                if (item.safetyMessage != null)
                  'safetyMessage': item.safetyMessage,
              })
          .toList(),
      'boundaries': const [
        'userText is supplied separately as the original Native text input; do not rewrite or replace it.',
        'SessionStateSnapshot facts and source references are supplied once through the Native session_state_context field; use provenance and do not duplicate them.',
        'rankedEvidence contains only evidence IDs whose complete blocks are present in this request context.',
        'knownEvidenceIds may include dropped candidates; they are not allowed citations.',
        'sourceId is an App lookup pointer, not a verification or authority claim.',
        'executionResults are App-projected results; preserve UNKNOWN and never claim an unverified action succeeded.',
        'actionCapabilityAllowlist is the exact App-owned capability set for this request; it is not user consent.',
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
