import 'dart:async';

import '../models/assistant_tool_result.dart';
import '../models/reasoning_request.dart';
import '../models/reasoning_response.dart';
import 'assistant_tool_invocation_ledger.dart';
import 'headless_tool_dispatcher.dart';
import 'reasoning_action_proposal_adapter.dart';
import 'reasoning_execution_result_adapter.dart';

enum AssistantToolExecutionCoordinatorStatus {
  authorizationDeclined,
  authorizationRejected,
  invocationAlreadyClaimed,
  claimConflict,
  claimAcquiredAndDispatched,
  existingTerminalReused,
  dispatchRejected,
  terminalUnavailable,
}

/// Result of one authorized, one-shot tool proposal lifecycle.
///
/// [executionResult] is always projected from a re-read of the durable ledger,
/// except when the ledger cannot be read back; in that case it is an UNKNOWN
/// result with no result values or source IDs. Raw executor output is never
/// returned to the reasoning layer directly.
class AssistantToolExecutionCoordinatorResult {
  const AssistantToolExecutionCoordinatorResult({
    required this.status,
    required this.diagnostics,
    this.gateResult,
    this.executionResult,
    this.plan,
  });

  final AssistantToolExecutionCoordinatorStatus status;
  final List<String> diagnostics;
  final ReasoningActionProposalGateResult? gateResult;
  final ToolExecutionPlan? plan;
  final ReasoningExecutionResult? executionResult;

  bool get wasDispatched =>
      status == AssistantToolExecutionCoordinatorStatus.claimAcquiredAndDispatched ||
      status == AssistantToolExecutionCoordinatorStatus.dispatchRejected;

  bool get canContinueReasoning => executionResult != null;
}

/// Coordinates the App-owned authorization, durable claim, Headless dispatch,
/// terminal persistence, and read-back boundary for one ACTION_PROPOSAL.
///
/// It deliberately has no BuildContext, UI, Native-channel, or navigation
/// dependency. The caller must obtain an explicit user confirmation before
/// setting [confirmedByUser] to true.
class AssistantToolExecutionCoordinator {
  const AssistantToolExecutionCoordinator({
    required AssistantToolInvocationLedger ledger,
    HeadlessToolDispatcher dispatcher = const HeadlessToolDispatcher(),
  })  : _ledger = ledger,
        _dispatcher = dispatcher;

  final AssistantToolInvocationLedger _ledger;
  final HeadlessToolDispatcher _dispatcher;

  Future<AssistantToolExecutionCoordinatorResult> executeConfirmedProposal({
    required int conversationId,
    required String invocationId,
    required ReasoningRequest request,
    required ReasoningActionProposalPreview preview,
    required bool confirmedByUser,
    FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
        executorOverride,
  }) async {
    if (conversationId <= 0 || request.sessionId != conversationId) {
      return const AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.authorizationRejected,
        diagnostics: ['TOOL_INVOCATION_CONVERSATION_SCOPE_MISMATCH'],
      );
    }

    final authorization =
        ReasoningActionProposalAdapter.authorizeAfterConfirmation(
      preview: preview,
      request: request,
      confirmedByUser: confirmedByUser,
    );
    if (!authorization.isAuthorized || authorization.plan == null) {
      final declined = authorization.status ==
          ReasoningActionProposalGateStatus.declined;
      return AssistantToolExecutionCoordinatorResult(
        status: declined
            ? AssistantToolExecutionCoordinatorStatus.authorizationDeclined
            : AssistantToolExecutionCoordinatorStatus.authorizationRejected,
        diagnostics: authorization.errors,
        gateResult: authorization,
      );
    }

    final plan = authorization.plan!;
    if (plan.origin != InvocationOrigin.aiDispatch ||
        plan.steps.length != 1) {
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.authorizationRejected,
        diagnostics: const ['TOOL_INVOCATION_PLAN_SHAPE_INVALID'],
        gateResult: authorization,
      );
    }

    final step = plan.steps.single;
    AssistantToolInvocationClaimStatus claimStatus;
    try {
      claimStatus = await _ledger.tryClaim(
        conversationId: conversationId,
        invocationId: invocationId,
        requestId: request.requestId,
        toolId: step.toolId,
        capabilityId: step.capabilityId,
        arguments: step.arguments,
      );
    } catch (_) {
      // The persistence acknowledgement may be lost after the claim commits.
      // Never dispatch when claim state cannot be established.
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.terminalUnavailable,
        diagnostics: const ['TOOL_INVOCATION_CLAIM_STATE_UNKNOWN_NO_DISPATCH'],
        gateResult: authorization,
        plan: plan,
        executionResult: _unknownExecutionResult(
          invocationId: invocationId,
          capabilityId: step.capabilityId,
          arguments: step.arguments,
          failureCode: 'TOOL_INVOCATION_CLAIM_STATE_UNKNOWN',
        ),
      );
    }

    switch (claimStatus) {
      case AssistantToolInvocationClaimStatus.alreadyClaimed:
        return AssistantToolExecutionCoordinatorResult(
          status: AssistantToolExecutionCoordinatorStatus.invocationAlreadyClaimed,
          diagnostics: const ['TOOL_INVOCATION_ALREADY_CLAIMED_NO_REPLAY'],
          gateResult: authorization,
          plan: plan,
          executionResult: _unknownExecutionResult(
            invocationId: invocationId,
            capabilityId: step.capabilityId,
            arguments: step.arguments,
            failureCode: 'TOOL_INVOCATION_ALREADY_CLAIMED',
          ),
        );
      case AssistantToolInvocationClaimStatus.conflictingClaim:
        return AssistantToolExecutionCoordinatorResult(
          status: AssistantToolExecutionCoordinatorStatus.claimConflict,
          diagnostics: const ['TOOL_INVOCATION_IDENTITY_CONFLICT_NO_REPLAY'],
          gateResult: authorization,
          plan: plan,
          executionResult: _unknownExecutionResult(
            invocationId: invocationId,
            capabilityId: step.capabilityId,
            arguments: step.arguments,
            failureCode: 'TOOL_INVOCATION_CLAIM_CONFLICT',
          ),
        );
      case AssistantToolInvocationClaimStatus.alreadyTerminal:
        return _readTerminal(
          conversationId: conversationId,
          invocationId: invocationId,
          capabilityId: step.capabilityId,
          expectedArguments: step.arguments,
          gateResult: authorization,
          plan: plan,
          status: AssistantToolExecutionCoordinatorStatus.existingTerminalReused,
          diagnostic: 'TOOL_INVOCATION_TERMINAL_REUSED_NO_REPLAY',
        );
      case AssistantToolInvocationClaimStatus.claimed:
        break;
    }

    HeadlessToolPlanExecutionResult dispatched;
    try {
      dispatched = await _dispatcher.executePlan(
        plan: plan,
        executorOverride: executorOverride,
      );
    } catch (_) {
      // An exception at this boundary cannot establish whether a side effect
      // occurred. Persist UNKNOWN when possible; never dispatch a second time.
      final unknown = AssistantToolResult(
        toolId: step.toolId,
        title: step.toolId,
        values: const {},
        arguments: step.arguments,
        sourceIds: const [],
        status: AssistantToolExecutionStatus.unknown,
        disclaimer: '工具执行调用异常，无法确认业务动作是否发生；不会自动重放。',
      );
      return _persistAndRead(
        conversationId: conversationId,
        invocationId: invocationId,
        capabilityId: step.capabilityId,
        expectedArguments: step.arguments,
        result: unknown,
        gateResult: authorization,
        plan: plan,
        dispatchRejected: false,
      );
    }

    if (!dispatched.isCompleted) {
      // The dispatcher guarantees that an invalid plan performs no execution.
      final rejected = AssistantToolResult(
        toolId: step.toolId,
        title: step.toolId,
        values: const {},
        arguments: step.arguments,
        sourceIds: const [],
        status: AssistantToolExecutionStatus.failed,
        disclaimer: '当前 Headless 注册表拒绝该计划；Dispatcher 未执行任何工具。',
      );
      return _persistAndRead(
        conversationId: conversationId,
        invocationId: invocationId,
        capabilityId: step.capabilityId,
        expectedArguments: step.arguments,
        result: rejected,
        gateResult: authorization,
        plan: plan,
        dispatchRejected: true,
      );
    }

    if (dispatched.results.length != 1) {
      // Gate currently builds one step only. An absent or extra result after
      // dispatch cannot be interpreted as success.
      final unknown = AssistantToolResult(
        toolId: step.toolId,
        title: step.toolId,
        values: const {},
        arguments: step.arguments,
        sourceIds: const [],
        status: AssistantToolExecutionStatus.unknown,
        disclaimer: '单步调用未返回唯一结果；执行状态按 UNKNOWN 处理且不会重放。',
      );
      return _persistAndRead(
        conversationId: conversationId,
        invocationId: invocationId,
        capabilityId: step.capabilityId,
        expectedArguments: step.arguments,
        result: unknown,
        gateResult: authorization,
        plan: plan,
        dispatchRejected: false,
      );
    }

    return _persistAndRead(
      conversationId: conversationId,
      invocationId: invocationId,
      capabilityId: step.capabilityId,
      expectedArguments: step.arguments,
      result: dispatched.results.single,
      gateResult: authorization,
      plan: plan,
      dispatchRejected: false,
    );
  }

  Future<AssistantToolExecutionCoordinatorResult> _persistAndRead({
    required int conversationId,
    required String invocationId,
    required String capabilityId,
    required Map<String, String> expectedArguments,
    required AssistantToolResult result,
    required ReasoningActionProposalGateResult gateResult,
    required ToolExecutionPlan plan,
    required bool dispatchRejected,
  }) async {
    try {
      await _ledger.recordResult(
        conversationId: conversationId,
        invocationId: invocationId,
        result: result,
      );
    } catch (_) {
      // A write can fail after the row is committed. Read back before deciding
      // that the terminal is unavailable; do not attempt execution again.
    }
    return _readTerminal(
      conversationId: conversationId,
      invocationId: invocationId,
      capabilityId: capabilityId,
      expectedArguments: expectedArguments,
      gateResult: gateResult,
      plan: plan,
      status: dispatchRejected
          ? AssistantToolExecutionCoordinatorStatus.dispatchRejected
          : AssistantToolExecutionCoordinatorStatus.claimAcquiredAndDispatched,
      diagnostic: 'TOOL_INVOCATION_TERMINAL_READ_BACK',
    );
  }

  Future<AssistantToolExecutionCoordinatorResult> _readTerminal({
    required int conversationId,
    required String invocationId,
    required String capabilityId,
    required Map<String, String> expectedArguments,
    required ReasoningActionProposalGateResult gateResult,
    required ToolExecutionPlan plan,
    required AssistantToolExecutionCoordinatorStatus status,
    required String diagnostic,
  }) async {
    try {
      final stored = await _ledger.loadTerminalResult(
        conversationId: conversationId,
        invocationId: invocationId,
      );
      if (stored == null) {
        return AssistantToolExecutionCoordinatorResult(
          status: AssistantToolExecutionCoordinatorStatus.terminalUnavailable,
          diagnostics: const ['TOOL_INVOCATION_TERMINAL_MISSING_NO_REPLAY'],
          gateResult: gateResult,
          plan: plan,
          executionResult: _unknownExecutionResult(
            invocationId: invocationId,
            capabilityId: capabilityId,
            arguments: expectedArguments,
            failureCode: 'TOOL_INVOCATION_TERMINAL_MISSING',
          ),
        );
      }
      final execution = ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: invocationId,
        result: stored,
        expectedArguments: expectedArguments,
      );
      return AssistantToolExecutionCoordinatorResult(
        status: status,
        diagnostics: [diagnostic, if (execution.status == ReasoningExecutionStatus.unknown) 'TOOL_INVOCATION_RESULT_UNKNOWN'],
        gateResult: gateResult,
        plan: plan,
        executionResult: execution,
      );
    } catch (_) {
      return AssistantToolExecutionCoordinatorResult(
        status: AssistantToolExecutionCoordinatorStatus.terminalUnavailable,
        diagnostics: const ['TOOL_INVOCATION_TERMINAL_READ_FAILED_NO_REPLAY'],
        gateResult: gateResult,
        plan: plan,
        executionResult: _unknownExecutionResult(
          invocationId: invocationId,
          capabilityId: capabilityId,
          arguments: expectedArguments,
          failureCode: 'TOOL_INVOCATION_TERMINAL_READ_FAILED',
        ),
      );
    }
  }

  ReasoningExecutionResult _unknownExecutionResult({
    required String invocationId,
    required String capabilityId,
    required Map<String, String> arguments,
    required String failureCode,
  }) =>
      ReasoningExecutionResult(
        invocationId: invocationId,
        capabilityId: capabilityId,
        status: ReasoningExecutionStatus.unknown,
        actualArguments: arguments,
        failureCode: failureCode,
        safetyMessage: 'App 无法确认本次工具调用的终态；保留 UNKNOWN，禁止自动重放或推测成功。',
      );
}
