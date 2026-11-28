import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/reasoning_knowledge_answer_adapter.dart';

AssistantKnowledgeSourceReference source(String id) =>
    AssistantKnowledgeSourceReference(
      sourceId: id,
      sourceLabel: '本地知识库',
      title: '测试条目',
      localBacklink: 'assets/data/test.json#id=1',
    );

AssistantKnowledgeContextResult knowledge({
  List<AssistantKnowledgeEvidenceReference> ranked = const [
    AssistantKnowledgeEvidenceReference(
      evidenceId: 'evidence-1',
      sourceId: 'source-1',
    ),
  ],
  List<String> known = const ['evidence-1', 'dropped-1'],
  List<AssistantKnowledgeSourceReference>? sources,
}) =>
    AssistantKnowledgeContextResult(
      text: '测试证据块',
      status: AssistantKnowledgeRetrievalStatus.retrieved,
      rankedEvidence: ranked,
      knownEvidenceIds: known,
      sources: sources ?? [source('source-1')],
    );

ReasoningRequest request(
  AssistantKnowledgeContextResult context, {
  String mode = 'learning',
  ReasoningAttachmentType? attachmentType,
  bool attachmentPromptGenerated = false,
}) =>
    ReasoningKnowledgeAnswerAdapter.createRequest(
      requestId: 'request-1',
      sessionId: 7,
      userText: '用户原始问题',
      mode: mode,
      sessionState: SessionStateSnapshot(
        sessionId: 7,
        revision: 'rev-1',
        status: SessionStateStatus.unknown,
        facts: const [],
        evidenceReferences: const [],
        diagnostics: const ['SESSION_STATE_UNKNOWN'],
      ),
      knowledge: context,
      attachmentType: attachmentType,
      attachmentPromptGenerated: attachmentPromptGenerated,
    );

String payload({
  String requestId = 'request-1',
  String responseKind = 'ANSWER',
  String status = 'COMPLETED',
  List<String> references = const ['evidence-1'],
  List<String> segments = const ['基于本地证据的解释'],
  List<String> omittedEvidenceIds = const ['dropped-1'],
  Object? proposal,
  Object? attachmentResult,
}) =>
    jsonEncode({
      'schemaVersion': 1,
      'requestId': requestId,
      'responseKind': responseKind,
      'status': status,
      'segments': segments,
      'referencedEvidenceIds': references,
      'unknowns': ['缺少用户确认'],
      'conflicts': ['两处资料表述不同'],
      'omittedEvidenceIds': omittedEvidenceIds,
      if (proposal != null) 'actionProposal': proposal,
      if (attachmentResult != null) 'attachmentResult': attachmentResult,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReasoningKnowledgeAnswerAdapter', () {

    test('image attachment observations are rendered as direct visual facts', () {
      final context = knowledge(ranked: const [], known: const [], sources: const []);
      final imageRequest = request(
        context,
        mode: 'consultation',
        attachmentType: ReasoningAttachmentType.image,
        attachmentPromptGenerated: true,
      );
      final decoded = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
        raw: payload(
          references: const [],
          omittedEvidenceIds: const [],
          attachmentResult: {
            'type': 'image',
            'observations': ['照片可见舌体偏淡红', '舌苔分布不均匀'],
          },
        ),
        request: imageRequest,
        knowledge: context,
      );

      expect(decoded.isUsable, isTrue);
      expect(decoded.answerText, contains('照片可直接观察到的内容'));
      expect(decoded.answerText, contains('照片可见舌体偏淡红'));
      expect(imageRequest.attachmentPromptGenerated, isTrue);
    });

    test('audio transcript is displayed as an unconfirmed draft', () {
      final context = knowledge(ranked: const [], known: const [], sources: const []);
      final audioRequest = request(
        context,
        mode: 'consultation',
        attachmentType: ReasoningAttachmentType.audio,
        attachmentPromptGenerated: true,
      );
      final decoded = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
        raw: payload(
          references: const [],
          omittedEvidenceIds: const [],
          attachmentResult: {
            'type': 'audio',
            'transcriptDraft': '这两天睡得不太好。',
          },
        ),
        request: audioRequest,
        knowledge: context,
      );

      expect(decoded.isUsable, isTrue);
      expect(decoded.answerText, contains('语音转写草稿（尚待用户核对'));
      expect(decoded.answerText, contains('这两天睡得不太好。'));
      expect(audioRequest.attachmentType, ReasoningAttachmentType.audio);
    });

    test('mode-neutral answer accepts no-evidence responses only when no ranked evidence was supplied', () {
      final emptyKnowledge = knowledge(
        ranked: const [],
        known: const [],
        sources: const [],
      );
      final automaticRequest = ReasoningKnowledgeAnswerAdapter.createRequest(
        requestId: 'request-1',
        sessionId: 7,
        userText: '你好',
        mode: 'automatic',
        sessionState: SessionStateSnapshot(
          sessionId: 7,
          revision: 'rev-1',
          status: SessionStateStatus.unknown,
          facts: const [],
          evidenceReferences: const [],
          diagnostics: const ['SESSION_STATE_UNKNOWN'],
        ),
        knowledge: emptyKnowledge,
      );

      final answer = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
        raw: payload(
          responseKind: 'ANSWER',
          references: const [],
          omittedEvidenceIds: const [],
          segments: const ['你好。'],
        ),
        request: automaticRequest,
        knowledge: emptyKnowledge,
      );

      expect(answer.isUsable, isTrue);
      expect(answer.answerText, startsWith('你好。\n'));
      expect(answer.answerText, contains('待确认：缺少用户确认'));
      expect(answer.answerText, contains('存在冲突：两处资料表述不同'));
      expect(answer.sourceIds, isEmpty);
    });

    test('mode-neutral adapter still requires citation when ranked evidence exists', () {
      final context = knowledge();
      final result = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
        raw: payload(
          references: const [],
          omittedEvidenceIds: const [],
        ),
        request: request(context),
        knowledge: context,
      );

      expect(result.isUsable, isFalse);
      expect(
        result.failureCode,
        'REASONING_RESPONSE_ANSWER_WITHOUT_EVIDENCE',
      );
    });

    test('mode-neutral adapter rejects capability-bearing requests before decode', () {
      final emptyKnowledge = knowledge(
        ranked: const [],
        known: const [],
        sources: const [],
      );
      final toolsRequest = ReasoningKnowledgeAnswerAdapter.createRequest(
        requestId: 'request-1',
        sessionId: 7,
        userText: '执行工具',
        mode: 'tools',
        sessionState: SessionStateSnapshot(
          sessionId: 7,
          revision: 'rev-1',
          status: SessionStateStatus.unknown,
          facts: const [],
          evidenceReferences: const [],
          diagnostics: const ['SESSION_STATE_UNKNOWN'],
        ),
        knowledge: emptyKnowledge,
        allowedCapabilityIds: const ['yuxiaji_omen'],
      );

      final result = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
        raw: payload(
          responseKind: 'ANSWER',
          references: const [],
          omittedEvidenceIds: const [],
        ),
        request: toolsRequest,
        knowledge: emptyKnowledge,
      );

      expect(result.isUsable, isFalse);
      expect(
        result.failureCode,
        'REASONING_CONVERSATION_PATH_EXECUTION_MODE_FORBIDDEN',
      );
    });

    test('tools mode cannot fall back to ordinary ANSWER even with an empty capability list', () {
      final emptyKnowledge = knowledge(
        ranked: const [],
        known: const [],
        sources: const [],
      );
      final toolsRequest = ReasoningKnowledgeAnswerAdapter.createRequest(
        requestId: 'request-1',
        sessionId: 7,
        userText: '运行一个工具',
        mode: 'tools',
        sessionState: SessionStateSnapshot(
          sessionId: 7,
          revision: 'rev-1',
          status: SessionStateStatus.unknown,
          facts: const [],
          evidenceReferences: const [],
          diagnostics: const ['SESSION_STATE_UNKNOWN'],
        ),
        knowledge: emptyKnowledge,
        allowedCapabilityIds: const [],
      );

      final result = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
        raw: payload(
          responseKind: 'ANSWER',
          references: const [],
          omittedEvidenceIds: const [],
        ),
        request: toolsRequest,
        knowledge: emptyKnowledge,
      );

      expect(result.isUsable, isFalse);
      expect(
        result.failureCode,
        'REASONING_CONVERSATION_PATH_EXECUTION_MODE_FORBIDDEN',
      );
    });

    test('mode-neutral conversation path rejects action proposals in every non-tool mode', () {
      final context = knowledge(
        ranked: const [],
        known: const [],
        sources: const [],
      );
      final actionProposal = payload(
        responseKind: 'ACTION_PROPOSAL',
        references: const [],
        omittedEvidenceIds: const [],
        proposal: {
          'proposalId': 'proposal-1',
          'capabilityId': 'dosage',
          'arguments': {'value': '1.5', 'unit': '两'},
        },
      );

      for (final mode in ['automatic', 'consultation', 'metaphysics']) {
        final result = ReasoningKnowledgeAnswerAdapter.decodeConversationAnswer(
          raw: actionProposal,
          request: request(context, mode: mode),
          knowledge: context,
        );
        expect(result.isUsable, isFalse, reason: '$mode must never execute tools');
        expect(result.answerText, isEmpty);
        expect(result.sourceIds, isEmpty);
      }
    });

    test('creates an exact one-entry context and resolves its request-local citation', () async {
      await FormulaRepository.load();
      final formula = FormulaRepository.getAll().first;
      final reference = AiContextResolver.buildFormulaContextRef(formula);
      final resolution = AiContextResolver.resolveFormula(ref: reference);
      expect(resolution.isResolved, isTrue);

      const evidenceId = 'context-entry-request-1';
      final context =
          ReasoningKnowledgeAnswerAdapter.createContextualEntryContext(
        entry: resolution.value!,
        evidenceId: evidenceId,
      );
      expect(context.sources, hasLength(1));
      expect(context.sources.single.sourceId, reference.sourceId);
      expect(
        context.sources.single.localBacklink,
        'assets/data/formulas.json#id=${formula.id}',
      );
      expect(context.rankedEvidence, hasLength(1));
      expect(context.rankedEvidence.single.evidenceId, evidenceId);
      expect(context.knownEvidenceIds, [evidenceId]);
      expect(context.modelContextText, contains(formula.name));
      expect(context.modelContextText, contains(formula.components.first.name));
      expect(context.modelContextText, isNot(contains(reference.sourceId)));
      expect(context.modelContextText, isNot(contains(reference.anchorVersion)));

      final requestValue = request(context);
      expect(requestValue.userText, '用户原始问题');
      expect(requestValue.rankedEvidenceIds, [evidenceId]);
      expect(requestValue.knownEvidenceIds, [evidenceId]);

      final answer = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(
          references: [evidenceId],
          omittedEvidenceIds: const [],
        ),
        request: requestValue,
        knowledge: context,
      );
      expect(answer.isUsable, isTrue);
      expect(answer.sourceIds, [reference.sourceId]);
      expect(answer.answerText, isNot(contains(evidenceId)));
      expect(answer.answerText, isNot(contains(reference.sourceId)));
    });

    test('rejects a contextual entry without a request-local evidence ID', () async {
      await FormulaRepository.load();
      final formula = FormulaRepository.getAll().first;
      final reference = AiContextResolver.buildFormulaContextRef(formula);
      final resolution = AiContextResolver.resolveFormula(ref: reference);

      expect(
        () => ReasoningKnowledgeAnswerAdapter.createContextualEntryContext(
          entry: resolution.value!,
          evidenceId: '  ',
        ),
        throwsArgumentError,
      );
    });

    test('builds request with exact evidence subset and original user text', () {
      final context = knowledge();
      final value = request(context);

      expect(value.userText, '用户原始问题');
      expect(value.requestId, 'request-1');
      expect(value.sessionId, 7);
      expect(value.rankedEvidenceIds, ['evidence-1']);
      expect(value.knownEvidenceIds, ['evidence-1', 'dropped-1']);
    });

    test('decodes response and backfills only referenced source IDs', () {
      final context = knowledge(
        sources: [source('source-1'), source('source-unused')],
      );
      final result = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(),
        request: request(context),
        knowledge: context,
      );

      expect(result.isUsable, isTrue);
      expect(result.answerText, contains('基于本地证据的解释'));
      expect(result.answerText, contains('待确认：缺少用户确认'));
      expect(result.answerText, contains('存在冲突：两处资料表述不同'));
      expect(result.sourceIds, ['source-1']);
      expect(result.answerText, isNot(contains('source-1')));
      expect(result.answerText, isNot(contains('evidence-1')));
      expect(result.answerText, isNot(contains('assets/data/test.json')));
    });

    test('fails closed on empty, invalid JSON and mismatched request IDs', () {
      final context = knowledge(sources: [source('source-1')]);
      final requestValue = request(context);

      for (final raw in ['', 'not-json', payload(requestId: 'other')]) {
        final result = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
          raw: raw,
          request: requestValue,
          knowledge: context,
        );
        expect(result.isUsable, isFalse);
        expect(result.answerText, isEmpty);
        expect(result.sourceIds, isEmpty);
      }
    });

    test('rejects dropped or unknown evidence IDs and unresolved sources', () {
      final context = knowledge(sources: [source('source-1')]);
      final requestValue = request(context);
      final dropped = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(references: ['dropped-1']),
        request: requestValue,
        knowledge: context,
      );
      expect(dropped.isUsable, isFalse);
      expect(dropped.failureCode, contains('UNRANKED_EVIDENCE'));

      final unknown = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(references: ['not-known-in-this-request']),
        request: requestValue,
        knowledge: context,
      );
      expect(unknown.isUsable, isFalse);
      expect(unknown.answerText, isEmpty);

      final unresolvedContext = knowledge(sources: []);
      final unresolved = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(),
        request: request(unresolvedContext),
        knowledge: unresolvedContext,
      );
      expect(unresolved.isUsable, isFalse);
      expect(unresolved.failureCode, contains('UNRANKED_EVIDENCE'));
    });


    test('rejects internal source IDs, evidence IDs and storage locators in answer text', () {
      final context = knowledge(sources: [source('source-1')]);
      final requestValue = request(context);
      final leakingSegments = [
        ['source-1 是对应条目。'],
        ['evidence-1 支持该结论。'],
        ['来源字段 sourceId: source-1'],
        ['本地路径 assets/data/test.json#id=1'],
      ];

      for (final segments in leakingSegments) {
        final result = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
          raw: payload(segments: segments),
          request: requestValue,
          knowledge: context,
        );
        expect(result.isUsable, isFalse);
        expect(
          result.failureCode,
          'REASONING_RESPONSE_CONTAINS_INTERNAL_PROVENANCE',
        );
        expect(result.answerText, isEmpty);
        expect(result.sourceIds, isEmpty);
      }
    });

    test('rejects an ANSWER with no request-local evidence references', () {
      final context = knowledge(sources: [source('source-1')]);
      final result = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(references: []),
        request: request(context),
        knowledge: context,
      );
      expect(result.isUsable, isFalse);
      expect(result.failureCode, 'REASONING_RESPONSE_ANSWER_WITHOUT_EVIDENCE');
      expect(result.answerText, isEmpty);
    });

    test('rejects empty response segments and duplicate or unresolvable source mappings', () {
      final context = knowledge(sources: [source('source-1')]);
      final requestValue = request(context);
      final empty = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(segments: const []),
        request: requestValue,
        knowledge: context,
      );
      expect(empty.isUsable, isFalse);
      expect(empty.failureCode, 'REASONING_RESPONSE_FIELD_INVALID');

      final duplicateEvidenceContext = knowledge(
        ranked: const [
          AssistantKnowledgeEvidenceReference(
            evidenceId: 'evidence-1',
            sourceId: 'source-1',
          ),
          AssistantKnowledgeEvidenceReference(
            evidenceId: 'evidence-2',
            sourceId: 'source-1',
          ),
        ],
        known: const ['evidence-1', 'evidence-2', 'dropped-1'],
        sources: [source('source-1')],
      );
      final duplicateMapped = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(references: ['evidence-1', 'evidence-2']),
        request: request(duplicateEvidenceContext),
        knowledge: duplicateEvidenceContext,
      );
      expect(duplicateMapped.isUsable, isTrue);
      expect(duplicateMapped.sourceIds, ['source-1']);
    });

    test('rejects action proposals because the learning path has no capabilities', () {
      final context = knowledge(sources: [source('source-1')]);
      final result = ReasoningKnowledgeAnswerAdapter.decodeAndResolve(
        raw: payload(
          responseKind: 'ACTION_PROPOSAL',
          proposal: {
            'proposalId': 'proposal-1',
            'capabilityId': 'dosage',
            'arguments': {'formulaId': 'formula-1'},
          },
        ),
        request: request(context),
        knowledge: context,
      );

      expect(result.isUsable, isFalse);
      expect(result.failureCode, 'REASONING_RESPONSE_CAPABILITY_NOT_REGISTERED');
    });


  });
}
