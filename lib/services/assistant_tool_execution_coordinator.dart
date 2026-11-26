import 'dart:async';

import '../models/assistant_tool_result.dart';
import '../models/reasoning_request.dart';
import '../models/reasoning_response.dart';
import '../models/tool_execution_plan.dart';
import 'assistant_tool_invocation_ledger.dart';
import 'headless_tool_dispatcher.dart';
import 'reasoning_action_proposal_adapter.dart';
import 'reasoning_action_proposal_gate.dart';
import 'reasoning_execution_result_adapter.dart';

/// Outcome of the App-owned, one-shot action lifecycle.
///
/// A [terminalReady] result is the only state that carries a model-facing
/// execution projection. Its contents always come from Ledger readback, never
/// directly from the dispatcher return value.
enum AssistantToolExecutionCoordinatorStatus {
  rejected,
  declined,
  alreadyRunning,
  conflictingClaim,
  persistenceUnknown,
  terminalReady,
}

class AssistantToolExecutionCoordinatorResult {
  const AssistantToolExecutionCoordinatorResult({
    required this.status,
    this.invocationId,
    this.toolResult,
    this.executionResult,
    this.failureCode,
    this.replayedTerminal = false,
  });

  final AssistantToolExecutionCoordinatorStatus status;
  final String? invocationId;
  final AssistantToolResult? toolResult;
  final ReasoningExecutionResult? executionResult;
  final String? failureCode;
  final bool replayedTerminal;

  bool get hasTerminalProjection =>
      status == AssistantToolExecutionCoordinatorStatus.terminalReady &&
      executionResult != null;
}

/// Coordinates the one-shot lifecycle for a single confirmed Core-4 proposal.
///
/// The ordering is fixed:
/// 1. Revalidate the App-owned preview against its original request.
/// 2. Require explicit user confirmation.
/// 3. Persist a unique claim.
/// 4. Only the winning claimant may call the existing Headless dispatcher.
/// 5. Persist the dispatcher outcome.
/// 6. Read the terminal back from Ledger and revalidate it.
/// 7. Project only that readback into the next ReasoningRequest.
///
/// This class never invokes Native inference, displays UI, or replays an
/// unresolved claim. Confirmation remains a screen-owned interaction.
class AssistantToolExecutionCoordinator {
  const AssistantToolExecutionCoordinator({
    required AssistantToolInvocationLedger ledger,
    HeadlessToolDispatcher dispatcher = const HeadlessToolDispatcher(),
  })  : _ledger = ledger,
        _dispatcher = dispatcher;

  final AssistantToolInvocationLedger _ledger;
  final HeadlessToolDispatcher _dispatcher;

  Future<AssistantToolExecutionCoordinatorResult> executeConfirmedProposal({
    required ReasoningRequest request,
    required ReasoningActionProposalPreview preview,
    required bool confirmedByUser,
    FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
        executorOverride,
  }) async {
    final authorization =
        ReasoningActionProposalAdapter.authorizeAfterConfirmation(
      preview: preview,
      request: request,
      confirmedByUser: confirmedByUser,
    );
    if (authorization.status == ReasoningActionProposalGateStatus.declined) {
      return const AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.declined,
        failureCode: 'ACTION_PROPOSAL_USER_DECLINED',
      );
    }
    if (!authorization.isAuthorized || authorization.plan == null) {
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.rejected,
        failureCode: authorization.errors.isEmpty
            ? 'ACTION_PROPOSAL_AUTHORIZATION_REJECTED'
            : authorization.errors.first,
      );
    }

    final plan = authorization.plan!;
    if (plan.origin != InvocationOrigin.aiDispatch ||
        plan.steps.length != 1) {
      return const AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.rejected,
        failureCode: 'ACTION_PROPOSAL_PLAN_SHAPE_INVALID',
      );
    }
    final step = plan.steps.single;
    final invocationId = plan.planId;

    AssistantToolInvocationClaimStatus claimStatus;
    try {
      claimStatus = await _ledger.tryClaim(
        conversationId: request.sessionId,
        invocationId: invocationId,
        requestId: request.requestId,
        toolId: step.toolId,
        capabilityId: step.capabilityId,
        arguments: step.arguments,
      );
    } catch (_) {
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.persistenceUnknown,
        invocationId: invocationId,
        failureCode: 'TOOL_INVOCATION_CLAIM_PERSISTENCE_UNKNOWN',
      );
    }

    switch (claimStatus) {
      case AssistantToolInvocationClaimStatus.conflictingClaim:
        return AssistantToolExecutionCoordinatorResult(
          status: AssistantToolExecutionCoordinatorStatus.conflictingClaim,
          invocationId: invocationId,
          failureCode: 'TOOL_INVOCATION_CLAIM_IDENTITY_CONFLICT',
        );
      case AssistantToolInvocationClaimStatus.alreadyClaimed:
        // A claim without a terminal can represent an in-flight or interrupted
        // side effect. Do not dispatch it again in this request.
        return AssistantToolExecutionCoordinatorResult(
          status: AssistantToolExecutionCoordinatorStatus.alreadyRunning,
          invocationId: invocationId,
          failureCode: 'TOOL_INVOCATION_ALREADY_CLAIMED_NO_REPLAY',
        );
      case AssistantToolInvocationClaimStatus.alreadyTerminal:
        return _readAndProject(
          conversationId: request.sessionId,
          invocationId: invocationId,
          expectedToolId: step.toolId,
          expectedArguments: step.arguments,
          replayed: true,
        );
      case AssistantToolInvocationClaimStatus.claimed:
        break;
    }

    AssistantToolResult dispatchedResult;
    try {
      final execution = await _dispatcher.executePlan(
        plan: plan,
        executorOverride: executorOverride,
      );
      if (!execution.isCompleted) {
        dispatchedResult = AssistantToolResult(
          toolId: step.toolId,
          title: step.toolId,
          values: const <String, String>{},
          arguments: step.arguments,
          status: AssistantToolExecutionStatus.failed,
          disclaimer: '执行计划未通过 Dispatcher 预检；未调用业务执行器。',
        );
      } else if (execution.results.length != 1) {
        dispatchedResult = AssistantToolResult(
          toolId: step.toolId,
          title: step.toolId,
          values: const <String, String>{},
          arguments: step.arguments,
          status: AssistantToolExecutionStatus.unknown,
          disclaimer: 'Dispatcher 未返回唯一的一步执行结果；本次不自动重放。',
        );
      } else {
        dispatchedResult = execution.results.single;
      }
    } catch (_) {
      // An exception outside the executor boundary is also uncertain: the
      // action may already have crossed a side-effect boundary.
      dispatchedResult = AssistantToolResult(
        toolId: step.toolId,
        title: step.toolId,
        values: const <String, String>{},
        arguments: step.arguments,
        status: AssistantToolExecutionStatus.unknown,
        disclaimer: '执行状态无法确认；本次不自动重放。',
      );
    }

    try {
      await _ledger.recordResult(
        conversationId: request.sessionId,
        invocationId: invocationId,
        result: dispatchedResult,
      );
    } catch (_) {
      // A write acknowledgement can be lost after the database committed.
      // Re-read once; never dispatch again to resolve an uncertain write.
    }

    return _readAndProject(
      conversationId: request.sessionId,
      invocationId: invocationId,
      expectedToolId: step.toolId,
      expectedArguments: step.arguments,
      replayed: false,
    );
  }

  Future<AssistantToolExecutionCoordinatorResult> _readAndProject({
    required int conversationId,
    required String invocationId,
    required String expectedToolId,
    required Map<String, String> expectedArguments,
    required bool replayed,
  }) async {
    try {
      final result = await _ledger.loadTerminalResult(
        conversationId: conversationId,
        invocationId: invocationId,
      );
      if (result == null) {
        return AssistantToolExecutionCoordinatorResult(
          status: AssistantToolExecutionCoordinatorStatus.persistenceUnknown,
          invocationId: invocationId,
          failureCode: 'TOOL_INVOCATION_TERMINAL_NOT_READABLE',
          replayedTerminal: replayed,
        );
      }
      final executionResult =
          ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: invocationId,
        result: result,
        expectedArguments: expectedArguments,
      );
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.terminalReady,
        invocationId: invocationId,
        toolResult: result,
        executionResult: executionResult,
        replayedTerminal: replayed,
      );
    } catch (_) {
      // Raw dispatcher output is deliberately not returned as a fallback.
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.persistenceUnknown,
        invocationId: invocationId,
        failureCode: 'TOOL_INVOCATION_TERMINAL_READBACK_INVALID',
        replayedTerminal: replayed,
      );
    }
  }
}
