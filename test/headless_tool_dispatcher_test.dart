import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/headless_tool_dispatcher.dart';

ToolExecutionStep _step(
  String toolId,
  String capabilityId,
  Map<String, String> arguments,
) =>
    ToolExecutionStep(
      toolId: toolId,
      capabilityId: capabilityId,
      arguments: arguments,
    );

AssistantToolResult _result(
  String toolId, {
  Map<String, String> arguments = const {},
}) =>
    AssistantToolResult(
      toolId: toolId,
      title: toolId,
      values: const {'result': 'ok'},
      arguments: arguments,
      sourceIds: const ['local-test'],
    );

ToolExecutionPlan _plan({
  required String id,
  required InvocationOrigin origin,
  required List<ToolExecutionStep> steps,
}) =>
    ToolExecutionPlan(planId: id, origin: origin, steps: steps);

void main() {
  group('HeadlessToolDispatcher', () {
    const arguments = <String, String>{'date': '2026-11-23'};

    test('dispatches a registered single-step plan with defensive argument copy', () async {
      var calls = 0;
      Map<String, String>? received;
      final mutableSource = {'date': '2026-11-23'};
      final plan = _plan(
        id: 'manual-yunqi',
        origin: InvocationOrigin.userManual,
        steps: [_step('yunqi', 'yunqi', mutableSource)],
      );
      mutableSource['date'] = '2099-01-01';

      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: plan,
        executorOverride: (value) {
          calls += 1;
          received = value;
          return _result('yunqi', arguments: value);
        },
      );

      expect(actual.status, HeadlessToolPlanExecutionStatus.completed);
      expect(actual.planId, 'manual-yunqi');
      expect(calls, 1);
      expect(received, arguments);
      expect(identical(received, mutableSource), isFalse);
      expect(actual.results.single.arguments, arguments);
      expect(
        () => plan.steps.single.arguments['date'] = '2099-01-01',
        throwsUnsupportedError,
      );
    });

    test('AI-origin cross-capability deterministic plan is not paywalled', () async {
      final calls = <String>[];
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(
          id: 'ai-cross-capability',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ],
        ),
        executorOverride: (arguments) {
          final toolId = calls.isEmpty ? 'yunqi' : 'bazi';
          calls.add(toolId);
          return _result(toolId, arguments: arguments);
        },
      );

      expect(actual.isCompleted, isTrue);
      expect(actual.toolIds, ['yunqi', 'bazi']);
      expect(calls, ['yunqi', 'bazi']);
      expect(actual.results, hasLength(2));
    });

    test('awaits asynchronous executor completion before returning plan result', () async {
      var completed = false;
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(
          id: 'async-yunqi',
          origin: InvocationOrigin.userManual,
          steps: [_step('yunqi', 'yunqi', arguments)],
        ),
        executorOverride: (received) async {
          await Future<void>.delayed(Duration.zero);
          completed = true;
          expect(received, arguments);
          return _result('yunqi', arguments: received);
        },
      );

      expect(completed, isTrue);
      expect(actual.isCompleted, isTrue);
      expect(actual.results, hasLength(1));
    });

    test('Page-only tools cannot execute even through a test override', () async {
      final pageOnly = AssistantToolRouter.byId('guji_library')!;
      expect(HeadlessToolDispatcher.hasExecutor(pageOnly.id), isFalse);
      var executorCalls = 0;

      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(
          id: 'invalid-page-tool',
          origin: InvocationOrigin.aiDispatch,
          steps: [_step(pageOnly.id, pageOnly.capabilityId, const {})],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result(pageOnly.id);
        },
      );

      expect(actual.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(actual.results, isEmpty);
      expect(executorCalls, 0);
      expect(HeadlessToolDispatcher.hasExecutor(pageOnly.id), isFalse);
    });

    test('rejects unregistered tools before execution', () async {
      var executorCalls = 0;
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(
          id: 'unknown-tool',
          origin: InvocationOrigin.aiDispatch,
          steps: [_step('unknown_tool', 'unknown_tool', const {})],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result('unknown_tool');
        },
      );

      expect(actual.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(executorCalls, 0);
    });

    test('rejects capability metadata mismatch before execution', () async {
      var executorCalls = 0;
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(
          id: 'invalid-plan',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'not-yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result('yunqi');
        },
      );

      expect(actual.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(executorCalls, 0);
    });

    test('stops later deterministic steps after a failed result', () async {
      final calls = <String>[];
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(
          id: 'stop-after-failure',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', arguments),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ],
        ),
        executorOverride: (value) {
          calls.add(calls.isEmpty ? 'yunqi' : 'bazi');
          return AssistantToolResult(
            toolId: calls.last,
            title: calls.last,
            status: AssistantToolExecutionStatus.failed,
            values: const {},
            arguments: value,
            sourceIds: const ['local-test'],
          );
        },
      );

      expect(actual.isCompleted, isTrue);
      expect(calls, ['yunqi']);
      expect(actual.results, hasLength(1));
      expect(actual.results.single.status, AssistantToolExecutionStatus.failed);
    });

    test('propagates executor errors without converting them to results', () async {
      final error = StateError('executor failure');
      await expectLater(
        const HeadlessToolDispatcher().executePlan(
          plan: _plan(
            id: 'executor-error',
            origin: InvocationOrigin.userManual,
            steps: [_step('yunqi', 'yunqi', arguments)],
          ),
          executorOverride: (_) => throw error,
        ),
        throwsA(same(error)),
      );
    });

    test('synchronous dispatch invokes an explicitly allowlisted adapter', () {
      final result = HeadlessToolDispatcher.executeSync(
        toolId: 'dosage',
        arguments: const {},
      );
      expect(result.toolId, 'dosage');
      expect(result.status, AssistantToolExecutionStatus.failed);
    });

    test('synchronous dispatch rejects async tools before invoking them', () {
      expect(
        () => HeadlessToolDispatcher.executeSync(
          toolId: 'chenggu',
          arguments: const {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('synchronous dispatch preserves an explicit device-local clock', () {
      final observedAt = DateTime(2026, 11, 23, 12, 34);
      final result = HeadlessToolDispatcher.executeSync(
        toolId: 'yuxiaji_omen',
        arguments: const {},
        clock: () => observedAt,
      );
      expect(DateTime.parse(result.values['App 本机日期时间']!).hour, observedAt.hour);
      expect(DateTime.parse(result.values['App 本机日期时间']!).minute, observedAt.minute);
    });
  });
}
