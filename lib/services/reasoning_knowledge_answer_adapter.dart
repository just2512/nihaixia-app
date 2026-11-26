import '../models/reasoning_request.dart';
import '../models/reasoning_response.dart';
import '../models/session_state_snapshot.dart';
import 'ai_context_prompt_builder.dart';
import 'ai_context_resolver.dart';
import 'assistant_knowledge_context.dart';
import 'reasoning_response_codec.dart';

/// Validates one knowledge-only Core-3 turn and resolves citations back to
/// App-owned source records. It intentionally has no capability registry.
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


  /// Materializes one explicitly anchored App knowledge entry as the complete
  /// request-local evidence for a contextual interpretation turn.
  ///
  /// This is not keyword retrieval or a CandidateEvidence projection: the
  /// source has already been resolved against its exact typed App anchor.
  /// App source IDs and backlinks stay in the source map, never in model text.
  static AssistantKnowledgeContextResult createContextualEntryContext({
    required AiResolvedKnowledgeEntry entry,
    required String evidenceId,
  }) {
    final normalizedEvidenceId = evidenceId.trim();
    if (normalizedEvidenceId.isEmpty) {
      throw ArgumentError.value(
        evidenceId,
        'evidenceId',
        'A contextual entry requires a request-local evidence ID.',
      );
    }
    final reference = entry.ref;
    if (reference.sourceId.trim().isEmpty ||
        reference.anchorId.trim().isEmpty ||
        reference.anchorVersion.trim().isEmpty) {
      throw ArgumentError(
        'A contextual entry requires a complete resolved App source reference.',
      );
    }
    final localBacklink = switch (reference.moduleId) {
      'formula' => () {
          final formulaId = entry.content['id'];
          if (formulaId is! String || formulaId.trim().isEmpty) {
            throw StateError('Resolved formula entry is missing its local asset ID.');
          }
          return 'assets/data/formulas.json#id=$formulaId';
        }(),
      // Other resolver-backed knowledge entries already store their stable
      // local locator in sourceId (for example herbs and Neijing records).
      _ => reference.sourceId,
    };
    return AssistantKnowledgeContextResult(
      text: AiContextPromptBuilder.buildKnowledgeEntryModelContext(
        entry: entry,
      ),
      sources: [
        AssistantKnowledgeSourceReference(
          sourceId: reference.sourceId,
          sourceLabel: 'App 当前知识条目',
          title: entry.title,
          localBacklink: localBacklink,
          sourceKind: reference.moduleId,
        ),
      ],
      status: AssistantKnowledgeRetrievalStatus.retrieved,
      knownEvidenceIds: [normalizedEvidenceId],
      rankedEvidence: [
        AssistantKnowledgeEvidenceReference(
          evidenceId: normalizedEvidenceId,
          sourceId: reference.sourceId,
        ),
      ],
    );
  }

  static ReasoningRequest createRequest({
    required String requestId,
    required int sessionId,
    required String userText,
    required String mode,
    required SessionStateSnapshot sessionState,
    required AssistantKnowledgeContextResult knowledge,
    List<String> allowedCapabilityIds = const [],
    List<ReasoningExecutionResult> executionResults = const [],
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
      executionResults: executionResults,
      allowedCapabilityIds: allowedCapabilityIds,
    );
  }

  static String evidenceIndexContext(ReasoningRequest request) =>
      request.rankedEvidence.isEmpty
          ? ''
          : '【本轮已完整提供、允许引用的证据 ID】\n' +
              request.rankedEvidence
                  .map((item) => '- evidenceId=${item.evidenceId}')
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

    if (response.responseKind == ReasoningResponseKind.answer &&
        response.referencedEvidenceIds.isEmpty) {
      return _failure('REASONING_RESPONSE_ANSWER_WITHOUT_EVIDENCE');
    }

    final sourceIdByEvidenceId = <String, String>{
      for (final item in request.rankedEvidence) item.evidenceId: item.sourceId,
    };
    final sourceById = <String, AssistantKnowledgeSourceReference>{
      for (final source in knowledge.sources) source.sourceId: source,
    };
    final resolvedSourceIds = <String>[];
    final resolvedEvidenceIds = <String>[];
    for (final evidenceId in response.referencedEvidenceIds) {
      final sourceId = sourceIdByEvidenceId[evidenceId];
      if (sourceId == null || sourceId.trim().isEmpty) {
        return _failure('REASONING_RESPONSE_EVIDENCE_SOURCE_MAPPING_MISSING');
      }
      if (!sourceById.containsKey(sourceId)) {
        return _failure('REASONING_RESPONSE_SOURCE_NOT_RESOLVED');
      }
      if (!resolvedSourceIds.contains(sourceId)) {
        resolvedSourceIds.add(sourceId);
      }
      resolvedEvidenceIds.add(evidenceId);
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
    // Internal evidence/source identifiers and local locators remain App-side
    // metadata; reject a model segment that tries to surface any of them.
    final internalIds = <String>{
      ...resolvedSourceIds,
      ...resolvedEvidenceIds,
      ...request.knownEvidenceIds,
      ...request.rankedEvidenceIds,
      ...sourceById.keys,
    }.where((value) => value.length >= 5);
    final internalBacklinks = sourceById.values
        .map((source) => source.localBacklink.trim())
        .where((value) => value.isNotEmpty);
    final containsInternalId = internalIds.any(
      (value) => RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(value)}([^A-Za-z0-9_]|\$)',
      ).hasMatch(text),
    );
    if (containsInternalId ||
        internalBacklinks.any((backlink) => text.contains(backlink)) ||
        RegExp(r'\b(?:sourceId|evidenceId)\s*[:=]', caseSensitive: false)
            .hasMatch(text) ||
        RegExp(r'(^|\s)(?:assets/|/data/(?:user|data)/)\S+')
            .hasMatch(text)) {
      return _failure('REASONING_RESPONSE_CONTAINS_INTERNAL_PROVENANCE');
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
