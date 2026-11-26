import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/services/assistant_tool_execution_coordinator.dart';
import 'package:nihaisha_app/services/assistant_tool_invocation_ledger.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_adapter.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_gate.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'support/in_memory_assistant_conversation_store.dart';

const _requestId = '0123456789abcdef0123456789abcdef';

SessionStateSnapshot _session(int id) => SessionStateSnapshot(
      sessionId: id,
      revision: 'rev-1',
      status: SessionStateStatus.restored,
      facts: const [],
      evidenceReferences: const [],
    );

ReasoningRequest _request(int sessionId) =>
    ReasoningActionProposalAdapter.createRequest(
      requestId: _requestId,
      sessionId: sessionId,
      userText: '请换算这项方剂剂量',
      sessionState: _session(sessionId),
      knowledge: const AssistantKnowledgeContextResult(text: ''),
      requestCapabilityAllowlist: const {'dosage'},
    );

ReasoningActionProposalPreview _preview(ReasoningRequest request) {
  final raw = jsonEncode({
    'schemaVersion': 1,
    'requestId': request.requestId,
    'responseKind': 'ACTION_PROPOSAL',
    'status': 'COMPLETED',
    'segments': ['模型提议调用工具。'],
    'referencedEvidenceIds': <String>[],
    'unknowns': <String>[],
    'conflicts': <String>[],
    'omittedEvidenceIds': <String>[],
    'actionProposal': {
      'proposalId': 'proposal-001',
      'capabilityId': 'dosage',
      'arguments': {
        'value': '3',
        'unit': '两',
        'standard': 'han',
      },
    },
  });
  final prepared = ReasoningActionProposalAdapter.decodeAndPrepare(
    raw: raw,
    request: request,
    knowledge: const AssistantKnowledgeContextResult(text: ''),
  );
  expect(prepared.requiresConfirmation, isTrue);
  expect(prepared.gateResult?.plan, isNull);
  return prepared.gateResult!.preview!;
}

void main() {
  group('AssistantToolExecutionCoordinator', () {
    late InMemoryAssistantConversationStore store;
    late AssistantToolInvocationLedger ledger;
    late AssistantToolExecutionCoordinator coordinator;
    late int conversationId;

    setUp(() async {
      store = InMemoryAssistantConversationStore();
      conversationId = await store.createAssistantConversation(mode: 'unified');
      ledger = AssistantToolInvocationLedger(store);
      coordinator = AssistantToolExecutionCoordinator(ledger: ledger);
    });

    test('decline never writes a claim or invokes the dispatcher', () async {
      final request = _request(conversationId);
      final preview = _preview(request);
      var calls = 0;

      final result = await coordinator.executeConfirmedProposal(
        request: request,
        preview: preview,
        confirmedByUser: false,
        executorOverride: (_) {
          calls++;
          return _successResult(const {});
        },
      );

      expect(result.status, AssistantToolExecutionCoordinatorStatus.declined);
      expect(result.executionResult, isNull);
      expect(calls, 0);
      expect(await store.getAssistantMessages(conversationId: conversationId), isEmpty);
    });

    test('persists claim before dispatch and projects only the ledger readback', () async {
      final request = _request(conversationId);
      final preview = _preview(request);
      var calls = 0;

      final result = await coordinator.executeConfirmedProposal(
        request: request,
        preview: preview,
        confirmedByUser: true,
        executorOverride: (arguments) {
          calls++;
          final rows = store.getAssistantMessages(conversationId: conversationId);
          return rows.then((messages) {
            expect(messages, hasLength(1));
            expect(messages.single['role'], 'tool');
            expect(messages.single['content'], 'TOOL_INVOCATION_CLAIMED');
            return _successResult(arguments);
          });
        },
      );

      expect(calls, 1);
      expect(result.status, AssistantToolExecutionCoordinatorStatus.terminalReady);
      expect(result.hasTerminalProjection, isTrue);
      expect(result.executionResult?.status, ReasoningExecutionStatus.succeeded);
      expect(result.executionResult?.actualArguments, preview.arguments);
      expect(result.executionResult?.resultValues, {'换算结果': '150g'});
      expect(result.executionResult?.sourceIds, ['local-engine:dosage:v1']);
      expect(result.executionResult?.invocationId, result.invocationId);

      final rows = await store.getAssistantMessages(conversationId: conversationId);
      expect(rows.map((row) => row['content']).toList(), [
        'TOOL_INVOCATION_CLAIMED',
        'TOOL_INVOCATION_TERMINAL',
      ]);
      expect(rows.every((row) => row['role'] == 'tool'), isTrue);
    });

    test('same terminal invocation is read back without a second dispatch', () async {
      final request = _request(conversationId);
      final preview = _preview(request);
      var calls = 0;

      Future<AssistantToolExecutionCoordinatorResult> invoke() =>
          coordinator.executeConfirmedProposal(
            request: request,
            preview: preview,
            confirmedByUser: true,
            executorOverride: (arguments) {
              calls++;
              return _successResult(arguments);
            },
          );

      final first = await invoke();
      final second = await invoke();

      expect(first.executionResult?.status, ReasoningExecutionStatus.succeeded);
      expect(second.status, AssistantToolExecutionCoordinatorStatus.terminalReady);
      expect(second.replayedTerminal, isTrue);
      expect(second.executionResult?.resultValues, {'换算结果': '150g'});
      expect(calls, 1);
    });

    test('an existing unresolved claim is never dispatched again', () async {
      final request = _request(conversationId);
      final preview = _preview(request);
      final invocationId =
          'rp-${request.requestId.substring(0, 8)}-${preview.proposalId}';
      final claimed = await ledger.tryClaim(
        conversationId: conversationId,
        invocationId: invocationId,
        requestId: request.requestId,
        toolId: preview.toolId,
        capabilityId: preview.capabilityId,
        arguments: preview.arguments,
      );
      expect(claimed, AssistantToolInvocationClaimStatus.claimed);

      var calls = 0;
      final result = await coordinator.executeConfirmedProposal(
        request: request,
        preview: preview,
        confirmedByUser: true,
        executorOverride: (_) {
          calls++;
          return _successResult(preview.arguments);
        },
      );

      expect(result.status, AssistantToolExecutionCoordinatorStatus.alreadyRunning);
      expect(result.executionResult, isNull);
      expect(result.failureCode, 'TOOL_INVOCATION_ALREADY_CLAIMED_NO_REPLAY');
      expect(calls, 0);
      expect(await store.getAssistantMessages(conversationId: conversationId),
          hasLength(1));
    });

    test('executor uncertainty remains UNKNOWN and carries no values or sources', () async {
      final request = _request(conversationId);
      final preview = _preview(request);

      final result = await coordinator.executeConfirmedProposal(
        request: request,
        preview: preview,
        confirmedByUser: true,
        executorOverride: (_) => throw StateError('simulated uncertain executor'),
      );

      expect(result.status, AssistantToolExecutionCoordinatorStatus.terminalReady);
      expect(result.executionResult?.status, ReasoningExecutionStatus.unknown);
      expect(result.executionResult?.resultValues, isEmpty);
      expect(result.executionResult?.sourceIds, isEmpty);
      expect(result.executionResult?.failureCode, 'TOOL_EXECUTION_UNKNOWN');
    });

    test('invalid success provenance is downgraded before model projection', () async {
      final request = _request(conversationId);
      final preview = _preview(request);

      final result = await coordinator.executeConfirmedProposal(
        request: request,
        preview: preview,
        confirmedByUser: true,
        executorOverride: (arguments) => AssistantToolResult(
          toolId: 'dosage',
          title: '剂量换算',
          values: const {'换算结果': '150g'},
          arguments: arguments,
          // A success without a source locator must not reach the model.
          sourceIds: const [],
        ),
      );

      expect(result.status, AssistantToolExecutionCoordinatorStatus.terminalReady);
      expect(result.executionResult?.status, ReasoningExecutionStatus.unknown);
      expect(result.executionResult?.resultValues, isEmpty);
      expect(result.executionResult?.sourceIds, isEmpty);
    });

    test('changed request scope rejects a preview before claim or dispatch', () async {
      final request = _request(conversationId);
      final preview = _preview(request);
      final changedRequest = ReasoningRequest(
        requestId: request.requestId,
        sessionId: request.sessionId,
        userText: request.userText,
        mode: 'tools',
        responseSchemaVersion: 1,
        sessionState: request.sessionState,
        allowedCapabilityIds: const {'solar_terms'},
      );
      var calls = 0;

      final result = await coordinator.executeConfirmedProposal(
        request: changedRequest,
        preview: preview,
        confirmedByUser: true,
        executorOverride: (_) {
          calls++;
          return _successResult(preview.arguments);
        },
      );

      expect(result.status, AssistantToolExecutionCoordinatorStatus.rejected);
      expect(result.failureCode, 'ACTION_PROPOSAL_REQUEST_ALLOWLIST_CHANGED');
      expect(calls, 0);
      expect(await store.getAssistantMessages(conversationId: conversationId), isEmpty);
    });
  });
}

AssistantToolResult _successResult(Map<String, String> arguments) =>
    AssistantToolResult(
      toolId: 'dosage',
      title: '剂量换算',
      values: const {'换算结果': '150g'},
      arguments: arguments,
      sourceIds: const ['local-engine:dosage:v1'],
    );
