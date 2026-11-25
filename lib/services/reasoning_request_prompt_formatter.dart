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

  static String formatSupplementalContext(ReasoningRequest request) {
    final sessionState = request.sessionState;
    final sessionStateMap = sessionState == null
        ? const <String, Object?>{
            'status': 'UNKNOWN',
            'facts': <Object?>[],
            'evidenceReferences': <Object?>[],
          }
        : (request.toMap()['sessionState'] as Map<String, Object?>);

    final envelope = <String, Object?>{
      'schemaVersion': 1,
      'requestId': request.requestId,
      'sessionId': request.sessionId,
      'mode': request.mode,
      'responseSchemaVersion': request.responseSchemaVersion,
      'sessionState': sessionStateMap,
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
    final encoded = jsonEncode(envelope);
    final formatted = '$header\n$encoded';
    if (sessionState != null &&
        formatted.length > SessionStateSnapshotPromptFormatter.maxCharacters +
            encoded.length) {
      throw StateError('REASONING_REQUEST_FORMATTER_BOUND_VIOLATION');
    }
    return formatted;
  }
}
