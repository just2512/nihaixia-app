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

ToolExecutionStep _step(String toolId, String capabilityId, String label) =>
    ToolExecutionStep(
      toolId: toolId,
      capabilityId: capabilityId,
      arguments: {'label': label},
    );

AssistantToolResult _result(String toolId) => AssistantToolResult(
      toolId: toolId,
      title: toolId,
      values: const {'result': 'ok'},
      arguments: const {},
      sourceIds: const ['local-test'],
    );


void main() {
  group('HeadlessToolDispatcher', () {
    const arguments = <String, String>{
      'date': '2026-11-23',
    };

    final expected = AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: const {'结果': '测试结果'},
      arguments: arguments,
      sourceIds: const ['local-engine:yunqi'],
    );

    test('invokes the registered executor once with the original argument map', () async {
      var calls = 0;
      Map<String, String>? receivedArguments;

      final actual = await HeadlessToolDispatcher.execute(
        toolId: AssistantToolRouter.yunqi.id,
        arguments: arguments,
        executorOverride: (received) {
          calls += 1;
          receivedArguments = received;
          return expected;
        },
      );

      expect(calls, 1);
      expect(identical(receivedArguments, arguments), isTrue);
      expect(identical(actual, expected), isTrue);
    });

    test('awaits an asynchronous executor and returns its typed result unchanged', () async {
      var completed = false;
      final actual = await HeadlessToolDispatcher.execute(
        toolId: AssistantToolRouter.yunqi.id,
        arguments: arguments,
        executorOverride: (received) async {
          await Future<void>.delayed(Duration.zero);
          completed = true;
          expect(received, arguments);
          return expected;
        },
      );

      expect(completed, isTrue);
      expect(identical(actual, expected), isTrue);
    });

    test('uses the test override for a Page-only definition without changing production metadata', () async {
      final pageOnly = AssistantToolRouter.byId('guji_library')!;
      expect(HeadlessToolDispatcher.hasExecutor(pageOnly.id), isFalse);

      final actual = await HeadlessToolDispatcher.execute(
        toolId: pageOnly.id,
        arguments: const {},
        executorOverride: (_) => AssistantToolResult(
          toolId: pageOnly.id,
          title: pageOnly.title,
          values: const {'状态': '测试'},
        ),
      );

      expect(actual.toolId, pageOnly.id);
      expect(HeadlessToolDispatcher.hasExecutor(pageOnly.id), isFalse);
    });

    test('rejects a Page-only tool when no executor is registered', () async {
      final pageOnly = AssistantToolRouter.byId('guji_library')!;
      await expectLater(
        HeadlessToolDispatcher.execute(
          toolId: pageOnly.id,
          arguments: const {},
        ),
        throwsA(isA<StateError>()),
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

      expect(
        DateTime.parse(result.values['App 本机日期时间']!).hour,
        observedAt.hour,
      );
      expect(
        DateTime.parse(result.values['App 本机日期时间']!).minute,
        observedAt.minute,
      );
    });

    test('propagates the executor error without converting it to a business result', () async {
      final error = StateError('executor failure');
      await expectLater(
        HeadlessToolDispatcher.execute(
          toolId: AssistantToolRouter.yunqi.id,
          arguments: arguments,
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
      final dispatcher = HeadlessToolDispatcher(featureAuthorizer: authorizer);
      final execution = await dispatcher.executePlan(
        plan: ToolExecutionPlan(
          planId: 'plan-denied',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', 'first'),
            _step('bazi', 'bazi', 'second'),
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

    test('keeps a temporarily unavailable authorization fail-closed before execution', () async {
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
        plan: ToolExecutionPlan(
          planId: 'plan-unavailable',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', 'first'),
            _step('bazi', 'bazi', 'second'),
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
        plan: ToolExecutionPlan(
          planId: 'manual-free',
          origin: InvocationOrigin.userManual,
          steps: [
            _step('yunqi', 'yunqi', 'first'),
            _step('bazi', 'bazi', 'second'),
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
        plan: ToolExecutionPlan(
          planId: 'same-capability-free',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'yunqi', 'first'),
            _step('yunqi', 'yunqi', 'second'),
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
        plan: ToolExecutionPlan(
          planId: 'invalid-plan',
          origin: InvocationOrigin.aiDispatch,
          steps: [
            _step('yunqi', 'not-yunqi', 'first'),
            _step('bazi', 'bazi', 'second'),
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
