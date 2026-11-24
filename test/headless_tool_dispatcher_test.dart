import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/headless_tool_dispatcher.dart';

ToolExecutionStep _step(String toolId, String capabilityId, Map<String, String> arguments) =>
    ToolExecutionStep(toolId: toolId, capabilityId: capabilityId, arguments: arguments);

AssistantToolResult _result(String toolId, {Map<String, String> arguments = const {}}) =>
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
}) => ToolExecutionPlan(planId: id, origin: origin, steps: steps);

void main() {
  group('HeadlessToolDispatcher', () {
    const arguments = <String, String>{'date': '2026-11-23'};

    test('dispatches a registered plan with a defensive argument copy', () async {
      var calls = 0;
      Map<String, String>? received;
      final source = {'date': '2026-11-23'};
      final plan = _plan(id: 'manual-yunqi', origin: InvocationOrigin.userManual,
        steps: [_step('yunqi', 'yunqi', source)]);
      source['date'] = '2099-01-01';

      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: plan,
        executorOverride: (value) {
          calls++;
          received = value;
          return _result('yunqi', arguments: value);
        },
      );

      expect(actual.status, HeadlessToolPlanExecutionStatus.completed);
      expect(calls, 1);
      expect(received, arguments);
      expect(identical(received, source), isFalse);
      expect(actual.results.single.arguments, arguments);
      expect(() => plan.steps.single.arguments['date'] = '2099-01-01',
          throwsUnsupportedError);
    });

    test('awaits asynchronous executor completion', () async {
      var completed = false;
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'async-yunqi', origin: InvocationOrigin.userManual,
          steps: [_step('yunqi', 'yunqi', arguments)]),
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
      var calls = 0;
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'page-only', origin: InvocationOrigin.aiDispatch,
          steps: [_step(pageOnly.id, pageOnly.capabilityId, const {})]),
        executorOverride: (_) {
          calls++;
          return _result(pageOnly.id);
        },
      );
      expect(actual.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(actual.results, isEmpty);
      expect(calls, 0);
    });

    test('rejects an unregistered tool before execution', () async {
      var calls = 0;
      final actual = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'unknown-tool', origin: InvocationOrigin.aiDispatch,
          steps: [_step('unknown_tool', 'unknown_tool', const {})]),
        executorOverride: (_) {
          calls++;
          return _result('unknown_tool');
        },
      );
      expect(actual.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(calls, 0);
    });

    test('sync dispatch invokes only explicitly allowlisted adapters', () {
      final result = HeadlessToolDispatcher.executeSync(toolId: 'dosage', arguments: const {});
      expect(result.toolId, 'dosage');
      expect(result.status, AssistantToolExecutionStatus.failed);
    });

    test('sync dispatch rejects async tools', () {
      expect(() => HeadlessToolDispatcher.executeSync(toolId: 'chenggu', arguments: const {}),
          throwsA(isA<StateError>()));
    });

    test('sync dispatch preserves explicit device-local clock', () {
      final observedAt = DateTime(2026, 11, 23, 12, 34);
      final result = HeadlessToolDispatcher.executeSync(
        toolId: 'yuxiaji_omen', arguments: const {}, clock: () => observedAt);
      expect(DateTime.parse(result.values['App 本机日期时间']!).hour, observedAt.hour);
      expect(DateTime.parse(result.values['App 本机日期时间']!).minute, observedAt.minute);
    });

    test('propagates executor errors without converting them', () async {
      final error = StateError('executor failure');
      await expectLater(
        const HeadlessToolDispatcher().executePlan(
          plan: _plan(id: 'executor-error', origin: InvocationOrigin.userManual,
            steps: [_step('yunqi', 'yunqi', arguments)]),
          executorOverride: (_) => throw error,
        ),
        throwsA(same(error)),
      );
    });

    test('AI-origin multi-capability plans are not business-layer paid gates', () async {
      var calls = 0;
      final execution = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'multi-capability', origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ]),
        executorOverride: (_) {
          calls++;
          return _result('yunqi');
        },
      );
      expect(execution.status, HeadlessToolPlanExecutionStatus.completed);
      expect(execution.capabilityIds, {'yunqi', 'bazi'});
      expect(calls, 2);
      expect(execution.results, hasLength(2));
    });

    test('manual multi-capability deterministic plans execute', () async {
      var calls = 0;
      final execution = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'manual-free', origin: InvocationOrigin.userManual,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ]),
        executorOverride: (_) {
          calls++;
          return _result('yunqi');
        },
      );
      expect(execution.isCompleted, isTrue);
      expect(calls, 2);
    });

    test('repeated deterministic steps within one capability execute', () async {
      var calls = 0;
      final execution = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'same-capability', origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('yunqi', 'yunqi', const {'date': '2026-11-24'}),
          ]),
        executorOverride: (_) {
          calls++;
          return _result('yunqi');
        },
      );
      expect(execution.isCompleted, isTrue);
      expect(calls, 2);
    });

    test('rejects capability metadata mismatch before side effects', () async {
      var calls = 0;
      final execution = await const HeadlessToolDispatcher().executePlan(
        plan: _plan(id: 'invalid-plan', origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'not-yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ]),
        executorOverride: (_) {
          calls++;
          return _result('yunqi');
        },
      );
      expect(execution.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(calls, 0);
    });
  });
}
