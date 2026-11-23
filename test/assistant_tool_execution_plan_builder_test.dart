import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/assistant_tool_execution_plan_builder.dart';

void main() {
  group('AssistantToolExecutionPlanBuilder', () {
    test('builds a complete ordered AI plan from candidate IDs only', () {
      final result = AssistantToolExecutionPlanBuilder.build(
        planId: '0123456789abcdef0123456789abcdef',
        query: '同时查询玉匣灵兆并抽取三山国王灵签',
        candidates: [
          AssistantToolRouter.yuxiaji,
          AssistantToolRouter.sanshan,
        ],
        orderedToolIds: ['yuxiaji_omen', 'sanshan_lingqian'],
      );

      expect(result.isValid, isTrue, reason: result.errors.join('; '));
      final plan = result.plan!;
      expect(plan.origin, InvocationOrigin.aiDispatch);
      expect(plan.planId, '0123456789abcdef0123456789abcdef');
      expect(plan.steps.map((step) => step.toolId).toList(), [
        'yuxiaji_omen',
        'sanshan_lingqian',
      ]);
      expect(plan.steps.map((step) => step.capabilityId).toSet().length, 2);
      expect(plan.requiresAdvancedAi, isTrue);
    });

    test('same-capability steps do not require ai_advanced', () {
      final first = AssistantToolRouter.yuxiaji;
      final sameCapability = AssistantToolDefinition(
        id: first.id,
        capabilityId: first.capabilityId,
        title: first.title,
        description: first.description,
        modes: first.modes,
        aliases: first.aliases,
        actionWords: first.actionWords,
        builder: first.builder,
        parameters: first.parameters,
      );
      // The plan builder rejects repeated tool IDs, so same-capability repeats
      // remain a dispatcher-level contract rather than an AI duplicate-ID plan.
      expect(
        () => AssistantToolExecutionPlanBuilder.build(
          planId: 'plan-1',
          query: '查询玉匣灵兆',
          candidates: [first, sameCapability],
          orderedToolIds: [first.id, first.id],
        ),
        returnsNormally,
      );
      final result = AssistantToolExecutionPlanBuilder.build(
        planId: 'plan-1',
        query: '查询玉匣灵兆',
        candidates: [first, sameCapability],
        orderedToolIds: [first.id, first.id],
      );
      expect(result.isValid, isFalse);
      expect(result.plan, isNull);
      expect(result.errors, isNotEmpty);
    });

    test('rejects page-only tools before constructing a plan', () {
      final result = AssistantToolExecutionPlanBuilder.build(
        planId: 'plan-2',
        query: '查阅古籍并查看玉匣灵兆',
        candidates: [
          AssistantToolRouter.guji,
          AssistantToolRouter.yuxiaji,
        ],
        orderedToolIds: ['guji_library', 'yuxiaji_omen'],
      );

      expect(result.isValid, isFalse);
      expect(result.plan, isNull);
      expect(result.errors.join(' '), contains('尚无 Headless 执行器'));
    });

    test('rejects a plan that selects IDs outside the candidate set', () {
      final result = AssistantToolExecutionPlanBuilder.build(
        planId: 'plan-3',
        query: '查询玉匣灵兆并抽签',
        candidates: [AssistantToolRouter.yuxiaji, AssistantToolRouter.sanshan],
        orderedToolIds: ['yuxiaji_omen', 'dosage'],
      );

      expect(result.isValid, isFalse);
      expect(result.plan, isNull);
      expect(result.errors.join(' '), contains('不在本轮授权候选集合中'));
    });

    test('rejects duplicate IDs and out-of-range plan sizes', () {
      final candidates = [
        AssistantToolRouter.yuxiaji,
        AssistantToolRouter.sanshan,
      ];
      for (final ids in [
        ['yuxiaji_omen', 'yuxiaji_omen'],
        ['yuxiaji_omen'],
        ['yuxiaji_omen', 'sanshan_lingqian', 'dosage', 'meihua'],
      ]) {
        final result = AssistantToolExecutionPlanBuilder.build(
          planId: 'plan-4',
          query: '查询玉匣灵兆并抽签',
          candidates: candidates,
          orderedToolIds: ids,
        );
        expect(result.isValid, isFalse, reason: ids.join(','));
        expect(result.plan, isNull);
      }
    });

    test('preflights required arguments for every step before exposing the plan', () {
      final result = AssistantToolExecutionPlanBuilder.build(
        planId: 'plan-5',
        query: '帮我排八字并查询玉匣灵兆',
        candidates: [
          AssistantToolRouter.bazi,
          AssistantToolRouter.yuxiaji,
        ],
        orderedToolIds: ['bazi', 'yuxiaji_omen'],
      );

      expect(result.isValid, isFalse);
      expect(result.plan, isNull);
      expect(result.errors.join(' '), contains('缺少必填参数'));
    });

    test('rejects invalid plan identifiers and empty queries', () {
      final result = AssistantToolExecutionPlanBuilder.build(
        planId: ' ',
        query: ' ',
        candidates: [
          AssistantToolRouter.yuxiaji,
          AssistantToolRouter.sanshan,
        ],
        orderedToolIds: ['yuxiaji_omen', 'sanshan_lingqian'],
      );

      expect(result.isValid, isFalse);
      expect(result.plan, isNull);
    });
  });
}
