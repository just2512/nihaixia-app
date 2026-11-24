import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';

ToolExecutionStep _step(String toolId, String capabilityId) =>
    ToolExecutionStep(
      toolId: toolId,
      capabilityId: capabilityId,
      arguments: const {'input': 'value'},
    );

void main() {
  group('ToolExecutionPlan', () {
    test('AI dispatch preserves origin and distinct capability metadata', () {
      final plan = ToolExecutionPlan(
        planId: 'plan-001',
        origin: InvocationOrigin.aiDispatch,
        steps: [
          _step('bazi', 'bazi_chart'),
          _step('yunqi', 'yunqi_calculation'),
        ],
      );

      expect(plan.origin, InvocationOrigin.aiDispatch);
      expect(plan.capabilityIds, {'bazi_chart', 'yunqi_calculation'});
      expect(plan.steps, hasLength(2));
    });

    test('repeated calls within one capability retain a single identity', () {
      final plan = ToolExecutionPlan(
        planId: 'plan-002',
        origin: InvocationOrigin.aiDispatch,
        steps: [
          _step('bazi', 'bazi_chart'),
          _step('bazi', 'bazi_chart'),
          _step('bazi', 'bazi_chart'),
        ],
      );

      expect(plan.steps, hasLength(3));
      expect(plan.capabilityIds, {'bazi_chart'});
      expect(plan.origin, InvocationOrigin.aiDispatch);
    });

    test('manual multi-capability execution preserves manual origin', () {
      final plan = ToolExecutionPlan(
        planId: 'plan-003',
        origin: InvocationOrigin.userManual,
        steps: [
          _step('bazi', 'bazi_chart'),
          _step('yunqi', 'yunqi_calculation'),
        ],
      );

      expect(plan.capabilityIds, hasLength(2));
      expect(plan.origin, InvocationOrigin.userManual);
    });

    test('structured diagnosis remains a deterministic single-step plan', () {
      final plan = ToolExecutionPlan(
        planId: 'plan-004',
        origin: InvocationOrigin.aiDispatch,
        steps: [_step('structured_diagnosis', 'structured_diagnosis')],
      );

      expect(plan.steps, hasLength(1));
      expect(plan.capabilityIds, {'structured_diagnosis'});
      expect(plan.origin, InvocationOrigin.aiDispatch);
    });

    test('complete plan and each argument map are immutable snapshots', () {
      final mutableArguments = <String, String>{'date': '2026-11-23'};
      final step = ToolExecutionStep(
        toolId: 'yunqi',
        capabilityId: 'yunqi_calculation',
        arguments: mutableArguments,
      );
      mutableArguments['date'] = '2099-01-01';

      final mutableSteps = <ToolExecutionStep>[step];
      final plan = ToolExecutionPlan(
        planId: 'plan-005',
        origin: InvocationOrigin.aiDispatch,
        steps: mutableSteps,
      );
      mutableSteps.clear();

      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.arguments['date'], '2026-11-23');
      expect(
        () => plan.steps.single.arguments['date'] = '2099-01-01',
        throwsUnsupportedError,
      );
      expect(() => plan.steps.add(step), throwsUnsupportedError);
    });

    test('registered tool capability IDs populate complete plan metadata', () {
      final bazi = AssistantToolRouter.bazi;
      final yunqi = AssistantToolRouter.yunqi;

      expect(bazi.capabilityId, 'bazi');
      expect(yunqi.capabilityId, 'yunqi');

      final plan = ToolExecutionPlan(
        planId: 'plan-registry-001',
        origin: InvocationOrigin.aiDispatch,
        steps: [
          ToolExecutionStep(
            toolId: bazi.id,
            capabilityId: bazi.capabilityId,
            arguments: const {},
          ),
          ToolExecutionStep(
            toolId: yunqi.id,
            capabilityId: yunqi.capabilityId,
            arguments: const {},
          ),
        ],
      );
      expect(plan.origin, InvocationOrigin.aiDispatch);
      expect(plan.capabilityIds, {'bazi', 'yunqi'});
    });

    test('rejects blank plan, tool and capability IDs and empty plans', () {
      expect(
        () => ToolExecutionPlan(
          planId: ' ',
          origin: InvocationOrigin.userManual,
          steps: [_step('tool', 'capability')],
        ),
        throwsArgumentError,
      );
      expect(
        () => ToolExecutionPlan(
          planId: 'plan-empty',
          origin: InvocationOrigin.userManual,
          steps: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => ToolExecutionStep(
          toolId: '',
          capabilityId: 'capability',
          arguments: const {},
        ),
        throwsArgumentError,
      );
      expect(
        () => ToolExecutionStep(
          toolId: 'tool',
          capabilityId: ' ',
          arguments: const {},
        ),
        throwsArgumentError,
      );
    });
  });
}
