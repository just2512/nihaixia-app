import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/reasoning_knowledge_answer_adapter.dart';

AssistantKnowledgeSourceReference source(String id) =>
    AssistantKnowledgeSourceReference(
      sourceId: id,
      sourceLabel: '本地知识库',
      title: '测试条目',
      localBacklink: 'assets/data/test.json#id=1',
      locatorStatus: 'RESOLVED',
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

ReasoningRequest request(AssistantKnowledgeContextResult context) =>
    ReasoningKnowledgeAnswerAdapter.createRequest(
      requestId: 'request-1',
      sessionId: 7,
      userText: '用户原始问题',
      mode: 'learning',
      sessionState: SessionStateSnapshot(
        sessionId: 7,
        revision: 'rev-1',
        status: SessionStateStatus.unknown,
        facts: const [],
        evidenceReferences: const [],
        diagnostics: const ['SESSION_STATE_UNKNOWN'],
      ),
      knowledge: context,
    );

String payload({
  String requestId = 'request-1',
  String responseKind = 'ANSWER',
  String status = 'COMPLETED',
  List<String> references = const ['evidence-1'],
  Object? proposal,
}) =>
    jsonEncode({
      'schemaVersion': 1,
      'requestId': requestId,
      'responseKind': responseKind,
      'status': status,
      'segments': ['基于本地证据的解释'],
      'referencedEvidenceIds': references,
      'unknowns': ['缺少用户确认'],
      'conflicts': ['两处资料表述不同'],
      'omittedEvidenceIds': ['dropped-1'],
      if (proposal != null) 'actionProposal': proposal,
    });

void main() {
  group('ReasoningKnowledgeAnswerAdapter', () {
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
      expect(result.citationFooter, contains('source-1'));
      expect(result.citationFooter, isNot(contains('source-unused')));
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
        expect(result.citationFooter, isEmpty);
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
