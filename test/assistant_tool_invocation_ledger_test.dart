import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/assistant_tool_invocation_ledger.dart';
import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  late InMemoryAssistantConversationStore store;
  late AssistantToolInvocationLedger ledger;
  late int conversationId;

  const invocationId = '0123456789abcdef0123456789abcdef';
  const requestId = 'abcdef0123456789abcdef0123456789';
  const arguments = <String, String>{'value': '3', 'unit': '两', 'standard': 'han'};

  setUp(() async {
    store = InMemoryAssistantConversationStore();
    ledger = AssistantToolInvocationLedger(store);
    conversationId = await store.createAssistantConversation(mode: 'tools');
  });

  AssistantToolResult successfulResult({
    Map<String, String> values = const {'换算结果': '150g'},
    List<String> sourceIds = const ['local-engine:dosage:v1'],
  }) =>
      AssistantToolResult(
        toolId: 'dosage',
        title: '剂量换算',
        values: values,
        sourceIds: sourceIds,
        arguments: arguments,
      );

  Future<AssistantToolInvocationClaimStatus> claim({
    String id = invocationId,
    int? conversation,
  }) =>
      ledger.tryClaim(
        conversationId: conversation ?? conversationId,
        invocationId: id,
        requestId: requestId,
        toolId: 'dosage',
        capabilityId: 'dosage',
        arguments: arguments,
      );

  test('writes a durable claim before dispatch and blocks duplicate claims', () async {
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);
    expect(await claim(), AssistantToolInvocationClaimStatus.alreadyClaimed);

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(1));
    expect(rows.single['role'], 'tool');
    expect(rows.single['invocation_key'], '$invocationId:claim');
    final metadata = jsonDecode(rows.single['metadata'] as String) as Map;
    expect(metadata['kind'], 'CLAIMED');
    expect(metadata['conversationId'], conversationId);
    expect(metadata['requestId'], requestId);
    expect(metadata['arguments'], arguments);
    expect(await ledger.listUnresolvedClaims(conversationId: conversationId), hasLength(1));
  });

  test('same invocation ID cannot be rebound to a different request or arguments', () async {
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);
    expect(
      await ledger.tryClaim(
        conversationId: conversationId,
        invocationId: invocationId,
        requestId: 'different-request',
        toolId: 'dosage',
        capabilityId: 'dosage',
        arguments: arguments,
      ),
      AssistantToolInvocationClaimStatus.conflictingClaim,
    );
    expect(
      await ledger.tryClaim(
        conversationId: conversationId,
        invocationId: invocationId,
        requestId: requestId,
        toolId: 'dosage',
        capabilityId: 'dosage',
        arguments: const {'value': '4'},
      ),
      AssistantToolInvocationClaimStatus.conflictingClaim,
    );
    expect(
      await store.getAssistantMessages(conversationId: conversationId),
      hasLength(1),
    );
  });

  test('invocation identity is scoped to one conversation', () async {
    final otherConversation = await store.createAssistantConversation(mode: 'tools');
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);
    expect(
      await claim(conversation: otherConversation),
      AssistantToolInvocationClaimStatus.claimed,
    );
  });

  test('persists actual SUCCEEDED result exactly once and refuses conflicting terminal', () async {
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);
    final actual = successfulResult();

    expect(
      await ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: actual,
      ),
      AssistantToolInvocationTerminalWriteStatus.recorded,
    );
    expect(
      await ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: actual,
      ),
      AssistantToolInvocationTerminalWriteStatus.alreadyRecorded,
    );
    expect(
      await ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: successfulResult(values: const {'换算结果': '999g'}),
      ),
      AssistantToolInvocationTerminalWriteStatus.conflictingTerminal,
    );

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(2));
    expect(rows.last['invocation_key'], '$invocationId:terminal');
    final terminal = jsonDecode(rows.last['metadata'] as String) as Map;
    expect(terminal['status'], 'succeeded');
    expect(terminal['actualArguments'], arguments);
    expect(terminal['resultValues'], {'换算结果': '150g'});
    expect(terminal['sourceIds'], ['local-engine:dosage:v1']);
    expect(await ledger.listUnresolvedClaims(conversationId: conversationId), isEmpty);
    expect(await claim(), AssistantToolInvocationClaimStatus.alreadyTerminal);
  });

  test('downgrades success with missing source provenance to UNKNOWN', () async {
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);
    expect(
      await ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: successfulResult(sourceIds: const []),
      ),
      AssistantToolInvocationTerminalWriteStatus.recorded,
    );

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    final terminal = jsonDecode(rows.last['metadata'] as String) as Map;
    expect(terminal['status'], 'unknown');
    expect(terminal['failureCode'], contains('RESULT_VALIDATION_FAILED'));
    expect(await claim(), AssistantToolInvocationClaimStatus.alreadyTerminal);
  });

  test('process recovery converts unresolved claims to UNKNOWN and never replays', () async {
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);

    // A new ledger instance represents restoration after process restart.
    final restoredLedger = AssistantToolInvocationLedger(store);
    expect(
      await restoredLedger.recoverUnresolvedClaims(conversationId: conversationId),
      [invocationId],
    );
    expect(
      await restoredLedger.recoverUnresolvedClaims(conversationId: conversationId),
      isEmpty,
    );
    expect(await restoredLedger.listUnresolvedClaims(conversationId: conversationId), isEmpty);
    expect(
      await restoredLedger.tryClaim(
        conversationId: conversationId,
        invocationId: invocationId,
        requestId: requestId,
        toolId: 'dosage',
        capabilityId: 'dosage',
        arguments: arguments,
      ),
      AssistantToolInvocationClaimStatus.alreadyTerminal,
    );

    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(2));
    final terminal = jsonDecode(rows.last['metadata'] as String) as Map;
    expect(terminal['status'], 'unknown');
    expect(terminal['interrupted'], isTrue);
    expect(terminal['failureCode'], 'PROCESS_INTERRUPTED_WITHOUT_TERMINAL_RESULT');
  });

  test('rejects a result without a durable claim', () async {
    expect(
      await ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: successfulResult(),
      ),
      AssistantToolInvocationTerminalWriteStatus.missingClaim,
    );
  });

  test('FAILED, NO_RESULT, CANCELLED, and UNKNOWN remain distinct terminal states', () async {
    final statuses = [
      AssistantToolExecutionStatus.failed,
      AssistantToolExecutionStatus.noResult,
      AssistantToolExecutionStatus.cancelled,
      AssistantToolExecutionStatus.unknown,
    ];
    for (var index = 0; index < statuses.length; index++) {
      final id = 'invocation-$index';
      expect(
        await ledger.tryClaim(
          conversationId: conversationId,
          invocationId: id,
          requestId: index.toString().padLeft(32, '0'),
          toolId: 'dosage',
          capabilityId: 'dosage',
          arguments: arguments,
        ),
        AssistantToolInvocationClaimStatus.claimed,
      );
      expect(
        await ledger.recordResult(
          conversationId: conversationId,
          invocationId: id,
          result: AssistantToolResult(
            toolId: 'dosage',
            title: '剂量换算',
            values: const {},
            arguments: arguments,
            status: statuses[index],
          ),
        ),
        AssistantToolInvocationTerminalWriteStatus.recorded,
      );
    }
    final rows = await store.getAssistantMessages(conversationId: conversationId);
    final terminalRows = rows.where((row) {
      final decoded = jsonDecode(row['metadata'] as String) as Map;
      return decoded['kind'] == 'TERMINAL';
    }).toList();
    expect(
      terminalRows.map((row) =>
          (jsonDecode(row['metadata'] as String) as Map)['status']).toList(),
      ['failed', 'noResult', 'cancelled', 'unknown'],
    );
  });

  test('argument mismatch cannot be persisted as SUCCEEDED', () async {
    expect(await claim(), AssistantToolInvocationClaimStatus.claimed);
    final mismatched = AssistantToolResult(
      toolId: 'dosage',
      title: '剂量换算',
      values: const {'换算结果': '150g'},
      sourceIds: const ['local-engine:dosage:v1'],
      arguments: const {'value': '4', 'unit': '两', 'standard': 'han'},
    );
    expect(
      await ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: mismatched,
      ),
      AssistantToolInvocationTerminalWriteStatus.recorded,
    );
    final rows = await store.getAssistantMessages(conversationId: conversationId);
    final terminal = jsonDecode(rows.last['metadata'] as String) as Map;
    expect(terminal['status'], 'unknown');
    expect(terminal['failureCode'], contains('ACTUAL_ARGUMENTS_MISMATCH'));
  });
}
