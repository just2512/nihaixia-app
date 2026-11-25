import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/services/reasoning_execution_result_adapter.dart';

AssistantToolResult _result({
  String toolId = 'dosage',
  AssistantToolExecutionStatus status =
      AssistantToolExecutionStatus.succeeded,
  Map<String, String> arguments = const {'formulaId': 'formula-1'},
  Map<String, String> values = const {'converted': '3 钱'},
  List<String> sourceIds = const ['local-engine:dosage'],
}) =>
    AssistantToolResult(
      toolId: toolId,
      title: '剂量换算',
      status: status,
      arguments: arguments,
      values: values,
      sourceIds: sourceIds,
    );

void main() {
  group('ReasoningExecutionResultAdapter', () {
    test('projects only a validated App success with actual args and sources', () {
      final result = ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: 'invoke-001',
        result: _result(),
        expectedArguments: const {'formulaId': 'formula-1'},
      );

      expect(result.invocationId, 'invoke-001');
      expect(result.capabilityId, 'dosage');
      expect(result.status, ReasoningExecutionStatus.succeeded);
      expect(result.actualArguments, {'formulaId': 'formula-1'});
      expect(result.resultValues, {'converted': '3 钱'});
      expect(result.sourceIds, ['local-engine:dosage']);
      expect(result.failureCode, isNull);
    });

    test('rejects a success missing actual arguments for a parameterized call', () {
      expect(
        () => ReasoningExecutionResultAdapter.fromAssistantToolResult(
          invocationId: 'invoke-002',
          result: _result(arguments: const {}),
          expectedArguments: const {'formulaId': 'formula-1'},
        ),
        throwsArgumentError,
      );
    });

    test('rejects success with mismatched actual arguments', () {
      expect(
        () => ReasoningExecutionResultAdapter.fromAssistantToolResult(
          invocationId: 'invoke-003',
          result: _result(
            arguments: const {'formulaId': 'formula-2'},
          ),
          expectedArguments: const {'formulaId': 'formula-1'},
        ),
        throwsArgumentError,
      );
    });

    test('preserves UNKNOWN and strips unverified values and source IDs', () {
      final result = ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: 'invoke-unknown',
        result: _result(
          status: AssistantToolExecutionStatus.unknown,
          values: const {'partial': 'not verified'},
          sourceIds: const ['local-engine:dosage'],
        ),
      );

      expect(result.status, ReasoningExecutionStatus.unknown);
      expect(result.failureCode, 'TOOL_EXECUTION_UNKNOWN');
      expect(result.resultValues, isEmpty);
      expect(result.sourceIds, isEmpty);
      expect(result.safetyMessage, contains('禁止自动重放'));
    });

    test('maps cancellation and no-result to distinct non-success failure codes', () {
      final cancelled =
          ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: 'invoke-cancelled',
        result: _result(
          status: AssistantToolExecutionStatus.cancelled,
          values: const {},
          sourceIds: const [],
        ),
      );
      final noResult =
          ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: 'invoke-no-result',
        result: _result(
          status: AssistantToolExecutionStatus.noResult,
          values: const {},
          sourceIds: const [],
        ),
      );

      expect(cancelled.status, ReasoningExecutionStatus.failed);
      expect(cancelled.failureCode, 'TOOL_EXECUTION_CANCELLED');
      expect(cancelled.resultValues, isEmpty);
      expect(noResult.status, ReasoningExecutionStatus.failed);
      expect(noResult.failureCode, 'TOOL_RESULT_NOT_RETURNED');
      expect(noResult.sourceIds, isEmpty);
    });

    test('preserves explicit executor failure without projecting its values', () {
      final failed = ReasoningExecutionResultAdapter.fromAssistantToolResult(
        invocationId: 'invoke-failed',
        result: _result(
          status: AssistantToolExecutionStatus.failed,
          values: const {'error': 'private error payload'},
          sourceIds: const ['local-engine:dosage'],
        ),
      );

      expect(failed.status, ReasoningExecutionStatus.failed);
      expect(failed.failureCode, 'TOOL_EXECUTION_FAILED');
      expect(failed.resultValues, isEmpty);
      expect(failed.sourceIds, isEmpty);
      expect(failed.actualArguments, {'formulaId': 'formula-1'});
    });

    test('rejects page-only and unknown tools as execution capabilities', () {
      expect(
        () => ReasoningExecutionResultAdapter.fromAssistantToolResult(
          invocationId: 'invoke-page',
          result: _result(
            toolId: 'guji_library',
            status: AssistantToolExecutionStatus.unknown,
            values: const {},
            sourceIds: const [],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResultAdapter.fromAssistantToolResult(
          invocationId: 'invoke-unknown-tool',
          result: _result(
            toolId: 'invented_tool',
            status: AssistantToolExecutionStatus.unknown,
            values: const {},
            sourceIds: const [],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects page-route pseudo source even when result claims success', () {
      expect(
        () => ReasoningExecutionResultAdapter.fromAssistantToolResult(
          invocationId: 'invoke-page-source',
          result: _result(
            sourceIds: const ['local-page-tool:dosage'],
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
