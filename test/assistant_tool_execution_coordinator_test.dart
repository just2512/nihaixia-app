import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/assistant_tool_invocation_ledger.dart';
import 'package:nihaisha_app/services/assistant_tool_execution_coordinator.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_adapter.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_gate.dart';
import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  late InMemoryAssistantConversationStore store;
  late AssistantToolInvocationLedger ledger;
  late AssistantToolExecutionCoordinator coordinator;
  late int conversationId;
  late ReasoningRequest request;
  late ReasoningActionProposalPreview preview;

  const requestId = '0123456789abcdef0123456789abcdef';
  const invocationId = 'abcdef0123456789abcdef0123456789';
  const expectedArguments = <String, String>{
    'value': '3',
    'unit': '两',
    'standard': 'han',
  };

  SessionStateSnapshot snapshot(int id) => SessionStateSnapshot(
        sessionId: id,
        revision: 'rev-1',
        status: SessionStateStatus.restored,
        facts: const [],
        evidenceReferences: const [],
      );

  AssistantToolResult success(Map<String, String> arguments) =>
      AssistantToolResult(
        toolId: 'dosage',
        title: '剂量换算',
        values: const {'换算结果': '150g'},
        sourceIds: const ['local-engine:dosage:v1'],
        arguments: arguments,
      );

  String proposalPayload() => jsonEncode({
        'schemaVersion': 1,
        'requestId': requestId,
        'responseKind': 'ACTION_PROPOSAL',
        'status': 'COMPLETED',
        'segments': ['调用 App 剂量换算能力。'],
        'referencedEvidenceIds': <String>[],
        'unknowns': <String>[],
        'conflicts': <String>[],
        'omittedEvidenceIds': <String>[],
        'actionProposal': {
          'proposalId': 'coordinator-proposal',
          'capabilityId': 'dosage',
          'arguments': expectedArguments,
        },
      });

  setUp(() async {
    store = InMemoryAssistantConversationStore();
    ledger = AssistantToolInvocationLedger(store);
    coordinator = AssistantToolExecutionCoordinator(ledger: ledger);
    conversationId = await store.createAssistantConversation(mode: 'tools');
    request = ReasoningActionProposalAdapter.createRequest(
      requestId: requestId,
      sessionId: conversationId,
      userText: '请换算 3 两的重量',
      sessionState: snapshot(conversationId),
      knowledge: const AssistantKnowledgeContextResult(text: ''),
      requestCapabilityAllowlist: const {'dosage'},
    );
    final prepared = ReasoningActionProposalAdapter.decodeAndPrepare(
      raw: proposalPayload(),
      request: request,
      knowledge: const AssistantKnowledgeContextResult(text: ''),
    );
    expect(prepared.requiresConfirmation, isTrue);
    preview = prepared.gateResult!.preview!;
  });

  test('decline creates neither a claim nor a business dispatch', () async {
    var dispatchCount = 0;

    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: false,
      executorOverride: (arguments) {
        dispatchCount++;
        return success(arguments);
      },
    );

    expect(result.status,
        AssistantToolExecutionCoordinatorStatus.authorizationDeclined);
    expect(result.executionResult, isNull);
    expect(dispatchCount, 0);
    expect(await store.getAssistantMessages(conversationId: conversationId), isEmpty);
  });

  test('explicit confirmation claims before dispatch and returns only ledger read-back', () async {
    var dispatchCount = 0;

    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: (arguments) async {
        final rows = await store.getAssistantMessages(conversationId: conversationId);
        expect(rows, hasLength(1));
        expect(rows.single['content'], 'TOOL_INVOCATION_CLAIMED');
        dispatchCount++;
        return success(arguments);
      },
    );

    expect(result.status,
        AssistantToolExecutionCoordinatorStatus.claimAcquiredAndDispatched);
    expect(result.executionResult?.status, ReasoningExecutionStatus.succeeded);
    expect(result.executionResult?.resultValues, {'换算结果': '150g'});
    expect(result.executionResult?.sourceIds, ['local-engine:dosage:v1']);
    expect(dispatchCount, 1);
    final rows = await store.getAssistantMessages(conversationId: conversationId);
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['content']),
        containsAll(['TOOL_INVOCATION_CLAIMED', 'TOOL_INVOCATION_TERMINAL']));
  });

  test('same terminal invocation is reused without a second dispatch', () async {
    var dispatchCount = 0;
    Future<AssistantToolResult> execute(Map<String, String> arguments) async {
      dispatchCount++;
      return success(arguments);
    }

    final first = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: execute,
    );
    final second = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: execute,
    );

    expect(first.executionResult?.status, ReasoningExecutionStatus.succeeded);
    expect(second.status,
        AssistantToolExecutionCoordinatorStatus.existingTerminalReused);
    expect(second.executionResult?.status, ReasoningExecutionStatus.succeeded);
    expect(dispatchCount, 1);
  });

  test('an unresolved claim is UNKNOWN and is never dispatched again', () async {
    await ledger.tryClaim(
      conversationId: conversationId,
      invocationId: invocationId,
      requestId: requestId,
      toolId: 'dosage',
      capabilityId: 'dosage',
      arguments: expectedArguments,
    );
    var dispatchCount = 0;

    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: (arguments) {
        dispatchCount++;
        return success(arguments);
      },
    );

    expect(result.status,
        AssistantToolExecutionCoordinatorStatus.invocationAlreadyClaimed);
    expect(result.executionResult?.status, ReasoningExecutionStatus.unknown);
    expect(result.executionResult?.resultValues, isEmpty);
    expect(result.executionResult?.sourceIds, isEmpty);
    expect(dispatchCount, 0);
  });

  test('a process-interrupted claim reuses UNKNOWN and never dispatches', () async {
    await ledger.tryClaim(
      conversationId: conversationId,
      invocationId: invocationId,
      requestId: requestId,
      toolId: 'dosage',
      capabilityId: 'dosage',
      arguments: expectedArguments,
    );
    await ledger.recoverUnresolvedClaims(conversationId: conversationId);
    var dispatchCount = 0;

    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: (arguments) {
        dispatchCount++;
        return success(arguments);
      },
    );

    expect(result.status,
        AssistantToolExecutionCoordinatorStatus.existingTerminalReused);
    expect(result.executionResult?.status, ReasoningExecutionStatus.unknown);
    expect(result.executionResult?.resultValues, isEmpty);
    expect(result.executionResult?.sourceIds, isEmpty);
    expect(dispatchCount, 0);
  });

  test('dispatcher exception is recorded and read back as UNKNOWN without replay', () async {
    var dispatchCount = 0;
    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: (arguments) {
        dispatchCount++;
        throw StateError('executor result lost after invocation');
      },
    );

    expect(result.status,
        AssistantToolExecutionCoordinatorStatus.claimAcquiredAndDispatched);
    expect(result.executionResult?.status, ReasoningExecutionStatus.unknown);
    expect(result.executionResult?.resultValues, isEmpty);
    expect(result.executionResult?.sourceIds, isEmpty);
    expect(dispatchCount, 1);
  });

  test('request from another conversation is rejected before a claim', () async {
    final otherRequest = ReasoningActionProposalAdapter.createRequest(
      requestId: requestId,
      sessionId: conversationId + 1,
      userText: '跨会话请求',
      sessionState: snapshot(conversationId + 1),
      knowledge: const AssistantKnowledgeContextResult(text: ''),
      requestCapabilityAllowlist: const {'dosage'},
    );
    var dispatchCount = 0;

    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: otherRequest,
      preview: preview,
      confirmedByUser: true,
      executorOverride: (arguments) {
        dispatchCount++;
        return success(arguments);
      },
    );

    expect(result.status,
        AssistantToolExecutionCoordinatorStatus.authorizationRejected);
    expect(result.executionResult, isNull);
    expect(dispatchCount, 0);
    expect(await store.getAssistantMessages(conversationId: conversationId), isEmpty);
  });

  test('invalid success provenance is downgraded to UNKNOWN before model handoff', () async {
    final result = await coordinator.executeConfirmedProposal(
      conversationId: conversationId,
      invocationId: invocationId,
      request: request,
      preview: preview,
      confirmedByUser: true,
      executorOverride: (arguments) => AssistantToolResult(
        toolId: 'dosage',
        title: '剂量换算',
        values: const {'换算结果': '150g'},
        // A successful tool result without its source must never reach reasoning.
        sourceIds: const [],
        arguments: arguments,
      ),
    );

    expect(result.executionResult?.status, ReasoningExecutionStatus.unknown);
    expect(result.executionResult?.resultValues, isEmpty);
    expect(result.executionResult?.sourceIds, isEmpty);
  });
}
