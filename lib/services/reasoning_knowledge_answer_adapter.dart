import '../models/reasoning_request.dart';
import '../models/reasoning_response.dart';
import '../models/session_state_snapshot.dart';
import 'assistant_knowledge_context.dart';
import 'reasoning_response_codec.dart';

/// Validates one knowledge-only Core-3 turn and maps accepted evidence IDs
/// to App-owned source IDs. Rendering remains in the normal answer and the
/// App-local source-navigation affordance; no citation footer is generated.
class ReasoningKnowledgeAnswerResult {
  ReasoningKnowledgeAnswerResult({
    required this.decodeResult,
    this.answerText = '',
    List<String> sourceIds = const [],
  }) : sourceIds = List.unmodifiable(sourceIds);

  final ReasoningResponseDecodeResult decodeResult;
  final String answerText;
  final List<String> sourceIds;

  bool get isUsable => decodeResult.isUsable;
  String? get failureCode => isUsable || decodeResult.diagnostics.isEmpty
      ? null
      : decodeResult.diagnostics.first;
}

class ReasoningKnowledgeAnswerAdapter {
  const ReasoningKnowledgeAnswerAdapter._();

  static ReasoningRequest createRequest({
    required String requestId,
    required int sessionId,
    required String userText,
    required String mode,
    required SessionStateSnapshot sessionState,
    required AssistantKnowledgeContextResult knowledge,
  }) {
    return ReasoningRequest(
      requestId: requestId,
      sessionId: sessionId,
      userText: userText,
      mode: mode,
      responseSchemaVersion: 1,
      sessionState: sessionState,
      rankedEvidence: knowledge.rankedEvidence
          .where((item) => knowledge.sourceIds.contains(item.sourceId))
          .map((item) => ReasoningEvidenceReference(
                evidenceId: item.evidenceId,
                sourceId: item.sourceId,
              ))
          .toList(growable: false),
      knownEvidenceIds: knowledge.knownEvidenceIds,
    );
  }

  static String evidenceIndexContext(ReasoningRequest request) =>
      request.rankedEvidence.isEmpty
          ? ''
          : '【本轮已完整提供、允许引用的证据 ID】\n' +
              request.rankedEvidence
                  .map((item) => '- evidenceId=${item.evidenceId}; sourceId=${item.sourceId}')
                  .join('\n');

  static ReasoningKnowledgeAnswerResult decodeAndResolve({
    required String raw,
    required ReasoningRequest request,
    required AssistantKnowledgeContextResult knowledge,
  }) {
    final decoded = ReasoningResponseCodec.decode(
      raw: raw,
      expectedRequestId: request.requestId,
      rankedEvidenceIds: request.rankedEvidenceIds.toSet(),
      knownEvidenceIds: request.knownEvidenceIds.toSet(),
      // Learning knowledge answers never receive action capabilities.
      allowedCapabilityIds: const <String>{},
    );
    final response = decoded.response;
    if (!decoded.isUsable || response == null) {
      return ReasoningKnowledgeAnswerResult(decodeResult: decoded);
    }
    if (response.actionProposal != null ||
        response.responseKind == ReasoningResponseKind.actionProposal) {
      return _failure('REASONING_KNOWLEDGE_PATH_ACTION_PROPOSAL_FORBIDDEN');
    }

    final sourceIdByEvidenceId = <String, String>{
      for (final item in request.rankedEvidence) item.evidenceId: item.sourceId,
    };
    final sourceById = <String, AssistantKnowledgeSourceReference>{
      for (final source in knowledge.sources) source.sourceId: source,
    };
    final resolvedSourceIds = <String>[];
    for (final evidenceId in response.referencedEvidenceIds) {
      final sourceId = sourceIdByEvidenceId[evidenceId];
      if (sourceId == null || sourceId.trim().isEmpty) {
        return _failure('REASONING_RESPONSE_EVIDENCE_SOURCE_MAPPING_MISSING');
      }
      final source = sourceById[sourceId];
      if (source == null) {
        return _failure('REASONING_RESPONSE_SOURCE_NOT_RESOLVED');
      }
      if (!resolvedSourceIds.contains(sourceId)) {
        resolvedSourceIds.add(sourceId);
      }
    }

    final sections = <String>[
      ...response.segments.map((item) => item.trim()).where((item) => item.isNotEmpty),
      if (response.unknowns.isNotEmpty)
        '待确认：${response.unknowns.join('；')}',
      if (response.conflicts.isNotEmpty)
        '存在冲突：${response.conflicts.join('；')}',
    ];
    final text = sections.join('\n\n');
    if (text.trim().isEmpty) {
      return _failure('REASONING_RESPONSE_EMPTY_RENDERED_ANSWER');
    }
    return ReasoningKnowledgeAnswerResult(
      decodeResult: decoded,
      answerText: text,
      sourceIds: resolvedSourceIds,
    );
  }

  static ReasoningKnowledgeAnswerResult _failure(String code) =>
      ReasoningKnowledgeAnswerResult(
        decodeResult: ReasoningResponseDecodeResult(
          status: ReasoningResponseStatus.unknown,
          diagnostics: [code],
        ),
      );
}
