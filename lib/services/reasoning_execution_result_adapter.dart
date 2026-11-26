import 'dart:convert';

import '../models/assistant_tool_result.dart';
import '../models/diagnosis_result_codec.dart';
import '../models/reasoning_request.dart';
import '../models/tcm_interview_task_state.dart';
import 'headless_tool_dispatcher.dart';

/// Projects an App-validated deterministic tool result into the immutable
/// Core-3 request contract. Model output is never accepted as execution proof.
///
/// NO_RESULT and CANCELLED are mapped to FAILED with distinct stable failure
/// codes because the frozen v1 reasoning status set is
/// NOT_STARTED/SUCCEEDED/FAILED/UNKNOWN. UNKNOWN remains UNKNOWN and is never
/// downgraded to an ordinary failure.
class ReasoningExecutionResultAdapter {
  const ReasoningExecutionResultAdapter._();

  static ReasoningExecutionResult fromAssistantToolResult({
    required String invocationId,
    required AssistantToolResult result,
    Map<String, String>? expectedArguments,
  }) {
    final capabilityId =
        HeadlessToolDispatcher.capabilityIdForTool(result.toolId);
    if (capabilityId == null ||
        !HeadlessToolDispatcher.hasExecutor(result.toolId)) {
      throw ArgumentError.value(
        result.toolId,
        'result.toolId',
        'REASONING_EXECUTION_TOOL_NOT_REGISTERED',
      );
    }

    final contractErrors = result.validateFor(result.toolId);
    if (contractErrors.isNotEmpty) {
      throw ArgumentError(
        'REASONING_EXECUTION_RESULT_CONTRACT_INVALID:${contractErrors.join('; ')}',
      );
    }

    if (expectedArguments != null) {
      final argumentErrors = result.validateArgumentsMatch(expectedArguments);
      if (argumentErrors.isNotEmpty &&
          (result.status == AssistantToolExecutionStatus.succeeded ||
              result.arguments.isNotEmpty)) {
        throw ArgumentError(
          'REASONING_EXECUTION_ARGUMENTS_MISMATCH:${argumentErrors.join('; ')}',
        );
      }
    }

    if (result.status == AssistantToolExecutionStatus.succeeded) {
      return ReasoningExecutionResult(
        invocationId: invocationId,
        capabilityId: capabilityId,
        status: ReasoningExecutionStatus.succeeded,
        actualArguments: result.arguments,
        resultValues: result.values,
        sourceIds: result.sourceIds,
      );
    }

    final mapped = _nonSuccessState(result.status);
    return ReasoningExecutionResult(
      invocationId: invocationId,
      capabilityId: capabilityId,
      status: mapped.status,
      actualArguments: result.arguments,
      failureCode: mapped.failureCode,
      safetyMessage: mapped.safetyMessage,
    );
  }

  /// Projects only a persisted completed TCM interview result.
  ///
  /// The task state is the App-owned completion proof: an in-progress,
  /// restored-without-result or text-only "normal baseline" task cannot be
  /// represented as a successful deterministic execution.
  static ReasoningExecutionResult fromCompletedTcmInterviewTaskState({
    required String invocationId,
    required TcmInterviewTaskState taskState,
  }) {
    final taskId = taskState.taskId.trim();
    final diagnosis = taskState.completedDiagnosis;
    if (taskId.isEmpty ||
        taskState.status != 'completed' ||
        diagnosis == null) {
      throw ArgumentError(
        'REASONING_DIAGNOSIS_EXECUTION_NOT_COMPLETED',
      );
    }

    final diagnosisJson = jsonEncode(DiagnosisResultCodec.toJson(diagnosis));
    final confirmedAnswersJson = jsonEncode(diagnosis.answers);
    if (diagnosisJson.isEmpty || confirmedAnswersJson.isEmpty) {
      throw ArgumentError('REASONING_DIAGNOSIS_EXECUTION_RESULT_EMPTY');
    }

    return ReasoningExecutionResult(
      invocationId: invocationId,
      capabilityId: 'structured_diagnosis',
      status: ReasoningExecutionStatus.succeeded,
      actualArguments: {
        'confirmedAnswers': confirmedAnswersJson,
      },
      resultValues: {
        'diagnosisResultJson': diagnosisJson,
      },
      sourceIds: const ['local-engine:diagnostic-engine'],
      safetyMessage:
          '这是 App DiagnosticEngine 已完成并持久化的结构化规则结果；'
          '只解释实际返回字段，不重新计算、补造或更改规则结论。',
    );
  }

  static ({
    ReasoningExecutionStatus status,
    String failureCode,
    String safetyMessage,
  }) _nonSuccessState(AssistantToolExecutionStatus status) =>
      switch (status) {
        AssistantToolExecutionStatus.failed => (
            status: ReasoningExecutionStatus.failed,
            failureCode: 'TOOL_EXECUTION_FAILED',
            safetyMessage: 'App 工具执行失败；不得将本轮改写为成功结果。',
          ),
        AssistantToolExecutionStatus.noResult => (
            status: ReasoningExecutionStatus.failed,
            failureCode: 'TOOL_RESULT_NOT_RETURNED',
            safetyMessage: 'App 未返回可验证结果；不得补造计算值或来源。',
          ),
        AssistantToolExecutionStatus.cancelled => (
            status: ReasoningExecutionStatus.failed,
            failureCode: 'TOOL_EXECUTION_CANCELLED',
            safetyMessage: 'App 工具执行已取消；不得描述为已完成。',
          ),
        AssistantToolExecutionStatus.unknown => (
            status: ReasoningExecutionStatus.unknown,
            failureCode: 'TOOL_EXECUTION_UNKNOWN',
            safetyMessage: 'App 工具执行状态未知；禁止自动重放或推测成功。',
          ),
        AssistantToolExecutionStatus.succeeded => throw StateError(
            'Succeeded results must use the validated success projection.',
          ),
      };
}
