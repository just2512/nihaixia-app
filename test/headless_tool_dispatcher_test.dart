import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/headless_tool_dispatcher.dart';

class _FakeFeatureAuthorizer implements FeatureAuthorizer {
  _FakeFeatureAuthorizer(this.decision);

  FeatureAuthorizationDecision decision;
  int calls = 0;
  final List<String> requestedFeatures = [];

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    calls += 1;
    requestedFeatures.add(featureId);
    return decision;
  }
}

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

    test('dispatches a registered single-step plan with a defensive argument copy', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.denied(
          featureId: 'ai_advanced',
          reason: FeatureAuthorizationFailureReason.unlicensed,
        ),
      );
      var calls = 0;
      Map<String, String>? received;
      final mutableSource = {'date': '2026-11-23'};
      final plan = _plan(
        id: 'manual-yunqi',
        origin: InvocationOrigin.userManual,
        steps: [_step('yunqi', 'yunqi', mutableSource)],
      );
      mutableSource['date'] = '2099-01-01';

      final actual = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
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
      expect(authorizer.calls, 0);
      expect(actual.results.single.arguments, arguments);
      expect(
        () => plan.steps.single.arguments['date'] = '2099-01-01',
        throwsUnsupportedError,
      );
    });

    test('awaits asynchronous executor completion before returning the plan result', () async {
      var completed = false;
      final actual = await HeadlessToolDispatcher(
        featureAuthorizer: const DenyByDefaultFeatureAuthorizer(),
      ).executePlan(
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

    test('Page-only tools cannot be executed even through a test override', () async {
      final pageOnly = AssistantToolRouter.byId('guji_library')!;
      expect(HeadlessToolDispatcher.hasExecutor(pageOnly.id), isFalse);
      var executorCalls = 0;
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.allowed(featureId: 'ai_advanced'),
      );

      final actual = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
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
      expect(authorizer.calls, 0);
      expect(HeadlessToolDispatcher.hasExecutor(pageOnly.id), isFalse);
    });

    test('rejects an unregistered tool before authorization or execution', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.allowed(featureId: 'ai_advanced'),
      );
      var executorCalls = 0;

      final actual = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
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
      expect(authorizer.calls, 0);
      expect(executorCalls, 0);
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

      expect(
        DateTime.parse(result.values['App 本机日期时间']!).hour,
        observedAt.hour,
      );
      expect(
        DateTime.parse(result.values['App 本机日期时间']!).minute,
        observedAt.minute,
      );
    });

    test('propagates executor errors without converting them to business results', () async {
      final error = StateError('executor failure');
      await expectLater(
        HeadlessToolDispatcher(
          featureAuthorizer: const DenyByDefaultFeatureAuthorizer(),
        ).executePlan(
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

    test('denies a cross-capability AI plan before any executor side effect', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.denied(
          featureId: 'ai_advanced',
          reason: FeatureAuthorizationFailureReason.unlicensed,
        ),
      );
      var executorCalls = 0;
      final execution = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
        plan: _plan(
          id: 'plan-denied',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result('yunqi');
        },
      );

      expect(execution.status, HeadlessToolPlanExecutionStatus.authorizationDenied);
      expect(execution.featureId, 'ai_advanced');
      expect(authorizer.requestedFeatures, ['ai_advanced']);
      expect(executorCalls, 0);
      expect(execution.results, isEmpty);
    });

    test('keeps temporarily unavailable authorization fail-closed before execution', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.temporarilyUnavailable(
          featureId: 'ai_advanced',
          reason: FeatureAuthorizationFailureReason.initializationTimeout,
        ),
      );
      var executorCalls = 0;
      final execution = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
        plan: _plan(
          id: 'plan-unavailable',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result('yunqi');
        },
      );

      expect(execution.status, HeadlessToolPlanExecutionStatus.authorizationUnavailable);
      expect(execution.failureReason, FeatureAuthorizationFailureReason.initializationTimeout);
      expect(executorCalls, 0);
    });

    test('does not charge manual multi-capability plans', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.denied(
          featureId: 'ai_advanced',
          reason: FeatureAuthorizationFailureReason.unlicensed,
        ),
      );
      var executorCalls = 0;
      final execution = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
        plan: _plan(
          id: 'manual-free',
          origin: InvocationOrigin.userManual,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('bazi', 'bazi', const {'birth_date': '1990-01-02'}),
          ],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result('yunqi');
        },
      );

      expect(execution.isCompleted, isTrue);
      expect(authorizer.calls, 0);
      expect(executorCalls, 2);
    });

    test('does not charge repeated steps in one AI capability', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.denied(
          featureId: 'ai_advanced',
          reason: FeatureAuthorizationFailureReason.unlicensed,
        ),
      );
      var executorCalls = 0;
      final execution = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
        plan: _plan(
          id: 'same-capability-free',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', const {'date': '2026-11-23'}),
            _step('yunqi', 'yunqi', const {'date': '2026-11-24'}),
          ],
        ),
        executorOverride: (_) {
          executorCalls += 1;
          return _result('yunqi');
        },
      );

      expect(execution.isCompleted, isTrue);
      expect(authorizer.calls, 0);
      expect(executorCalls, 2);
    });

    test('rejects capability metadata mismatch before authorization or execution', () async {
      final authorizer = _FakeFeatureAuthorizer(
        FeatureAuthorizationDecision.allowed(featureId: 'ai_advanced'),
      );
      var executorCalls = 0;
      final execution = await HeadlessToolDispatcher(
        featureAuthorizer: authorizer,
      ).executePlan(
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

      expect(execution.status, HeadlessToolPlanExecutionStatus.invalidPlan);
      expect(authorizer.calls, 0);
      expect(executorCalls, 0);
    });
  });
}
