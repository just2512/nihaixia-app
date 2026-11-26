import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/assistant_reasoning_turn_ledger.dart';
import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  late InMemoryAssistantConversationStore store;
  late AssistantReasoningTurnLedger ledger;
  late int conversationId;

  const requestId = '0123456789abcdef0123456789abcdef';
  const userText = '请解释上一轮规则结果的依据。';

  setUp(() async {
    store = InMemoryAssistantConversationStore();
    ledger = AssistantReasoningTurnLedger(store);
    conversationId = await store.createAssistantConversation(mode: 'consultation');
  });

  Future<AssistantReasoningTurnStartStatus> begin({
    String id = requestId,
    String text = userText,
    String mode = 'consultation',
    int? session,
  }) =>
      ledger.begin(
        conversationId: session ?? conversationId,
        requestId: id,
        mode: mode,
        userText: text,
      );

  test('persists a hidden pending request before Native inference', () async {
    expect(await begin(), AssistantReasoningTurnStartStatus.started);
    expect(await begin(), AssistantReasoningTurnStartStatus.alreadyPending);

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(1));
    expect(rows.single['role'], 'tool');
    expect(rows.single['content'], 'REASONING_TURN_PENDING');
    expect(
      rows.single['invocation_key'],
      'reasoning:$requestId:pending',
    );
    final payload = jsonDecode(rows.single['metadata'] as String) as Map;
    expect(payload['kind'], 'PENDING');
    expect(payload['conversationId'], conversationId);
    expect(payload['requestId'], requestId);
    expect(payload['mode'], 'consultation');
    expect(payload['userText'], userText);
    expect(
      (await ledger.load(conversationId: conversationId, requestId: requestId))
          ?.status,
      AssistantReasoningTurnStatus.pending,
    );
  });

  test('request identity cannot be rebound to another mode or user text', () async {
    expect(await begin(), AssistantReasoningTurnStartStatus.started);
    expect(
      await begin(text: '不同的用户原文'),
      AssistantReasoningTurnStartStatus.conflictingRequest,
    );
    expect(
      await begin(mode: 'automatic'),
      AssistantReasoningTurnStartStatus.conflictingRequest,
    );
    expect(
      await store.getAssistantMessages(conversationId: conversationId),
      hasLength(1),
    );
  });

  test('finalized result is persisted once with validated answer and source IDs', () async {
    expect(await begin(), AssistantReasoningTurnStartStatus.started);
    expect(
      await ledger.recordTerminal(
        conversationId: conversationId,
        requestId: requestId,
        status: AssistantReasoningTurnStatus.finalized,
        answerText: '这条规则的适用条件是……',
        sourceIds: const ['classic:shanghan:clause-001'],
      ),
      AssistantReasoningTurnTerminalWriteStatus.recorded,
    );
    expect(
      await ledger.recordTerminal(
        conversationId: conversationId,
        requestId: requestId,
        status: AssistantReasoningTurnStatus.finalized,
        answerText: '这条规则的适用条件是……',
        sourceIds: const ['classic:shanghan:clause-001'],
      ),
      AssistantReasoningTurnTerminalWriteStatus.alreadyRecorded,
    );
    expect(
      await ledger.recordTerminal(
        conversationId: conversationId,
        requestId: requestId,
        status: AssistantReasoningTurnStatus.finalized,
        answerText: '被篡改的答案',
        sourceIds: const ['classic:shanghan:clause-001'],
      ),
      AssistantReasoningTurnTerminalWriteStatus.conflictingTerminal,
    );

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(2));
    expect(rows.last['role'], 'tool');
    expect(rows.last['invocation_key'], 'reasoning:$requestId:terminal');
    final payload = jsonDecode(rows.last['metadata'] as String) as Map;
    expect(payload['status'], 'FINALIZED');
    expect(payload['answerText'], '这条规则的适用条件是……');
    expect(payload['sourceIds'], ['classic:shanghan:clause-001']);
    expect(
      (await ledger.load(conversationId: conversationId, requestId: requestId))
          ?.status,
      AssistantReasoningTurnStatus.finalized,
    );
  });

  test('process recovery converts unresolved requests to UNKNOWN without replay', () async {
    expect(await begin(), AssistantReasoningTurnStartStatus.started);

    final restartedLedger = AssistantReasoningTurnLedger(store);
    expect(
      await restartedLedger.recoverInterrupted(conversationId: conversationId),
      [requestId],
    );
    expect(
      await restartedLedger.recoverInterrupted(conversationId: conversationId),
      isEmpty,
    );
    expect(
      await begin(),
      AssistantReasoningTurnStartStatus.alreadyTerminal,
    );

    final record = await restartedLedger.load(
      conversationId: conversationId,
      requestId: requestId,
    );
    expect(record?.status, AssistantReasoningTurnStatus.unknown);
    expect(record?.interrupted, isTrue);
    expect(record?.failureCode, 'PROCESS_INTERRUPTED_WITHOUT_TERMINAL_ACK');
    expect(record?.answerText, isNull);
    expect(record?.sourceIds, isEmpty);

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(2));
    expect(rows.last['content'], 'REASONING_TURN_UNKNOWN');
  });

  test('rejected request remains distinct from interrupted UNKNOWN', () async {
    expect(await begin(), AssistantReasoningTurnStartStatus.started);
    expect(
      await ledger.recordTerminal(
        conversationId: conversationId,
        requestId: requestId,
        status: AssistantReasoningTurnStatus.rejected,
        failureCode: 'REASONING_RESPONSE_INVALID',
      ),
      AssistantReasoningTurnTerminalWriteStatus.recorded,
    );
    final record = await ledger.load(
      conversationId: conversationId,
      requestId: requestId,
    );
    expect(record?.status, AssistantReasoningTurnStatus.rejected);
    expect(record?.interrupted, isFalse);
    expect(record?.answerText, isNull);
  });

  test('request IDs are scoped to the conversation owner', () async {
    final other = await store.createAssistantConversation(mode: 'consultation');
    expect(await begin(), AssistantReasoningTurnStartStatus.started);
    expect(
      await begin(session: other),
      AssistantReasoningTurnStartStatus.started,
    );
    expect(
      await ledger.load(conversationId: other, requestId: requestId),
      isNotNull,
    );
  });

  test('invalid modes and malformed terminal payloads are rejected', () async {
    expect(
      () => ledger.begin(
        conversationId: conversationId,
        requestId: requestId,
        mode: 'tools',
        userText: userText,
      ),
      throwsArgumentError,
    );
    expect(await begin(), AssistantReasoningTurnStartStatus.started);
    expect(
      () => ledger.recordTerminal(
        conversationId: conversationId,
        requestId: requestId,
        status: AssistantReasoningTurnStatus.unknown,
        answerText: '不得携带成功答案',
        failureCode: 'PROCESS_INTERRUPTED',
      ),
      throwsArgumentError,
    );
  });
}
