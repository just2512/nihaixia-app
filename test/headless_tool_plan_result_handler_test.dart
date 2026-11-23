import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/headless_tool_dispatcher.dart';
import 'package:nihaisha_app/services/headless_tool_plan_result_handler.dart';

void main() {
  group('HeadlessToolPlanResultHandler', () {
    final tools = [
      AssistantToolRouter.yuxiaji,
      AssistantToolRouter.sanshan,
    ];
    final plan = ToolExecutionPlan(
      planId: 'plan-result-01',
      origin: InvocationOrigin.aiDispatch,
      steps: [
        ToolExecutionStep(
          toolId: 'yuxiaji_omen',
          capabilityId: 'yuxiaji_omen',
          arguments: const {},
        ),
        ToolExecutionStep(
          toolId: 'sanshan_lingqian',
          capabilityId: 'sanshan_lingqian',
          arguments: const {},
        ),
      ],
    );

    test('keeps every successful result, source and tool identity separate', () {
      final execution = HeadlessToolPlanExecutionResult(
        planId: plan.planId,
        status: HeadlessToolPlanExecutionStatus.completed,
        toolIds: plan.steps.map((step) => step.toolId),
        capabilityIds: plan.capabilityIds,
        results: [
          const AssistantToolResult(
            toolId: 'yuxiaji_omen',
            title: '玉匣灵兆',
            values: {'原文': '面热民俗条目'},
            sourceIds: ['local-knowledge:yuxiaji'],
            arguments: {},
          ),
          const AssistantToolResult(
            toolId: 'sanshan_lingqian',
            title: '三山灵签',
            values: {'签号': '第八签', '签文': '原始签文'},
            sourceIds: ['local-knowledge:sanshan'],
            arguments: {},
          ),
        ],
      );

      final result = HeadlessToolPlanResultHandler.handle(
        userText: '查询玉匣灵兆并抽取三山灵签',
        plan: plan,
        tools: tools,
        execution: execution,
        aiReady: true,
      );

      expect(result.allStepsSucceeded, isTrue);
      expect(result.steps, hasLength(2));
      expect(result.responseText, contains('玉匣灵兆执行结果'));
      expect(result.responseText, contains('三山灵签执行结果'));
      expect(result.sourceIds, [
        'local-knowledge:yuxiaji',
        'local-knowledge:sanshan',
      ]);
      expect(result.canInterpret, isTrue);
      expect(result.autoInterpret, isTrue);
      expect(result.interpretationPrompt, contains('分别解释'));
    });

    test('reports unexecuted later steps after an earlier non-success result', () {
      final execution = HeadlessToolPlanExecutionResult(
        planId: plan.planId,
        status: HeadlessToolPlanExecutionStatus.completed,
        toolIds: plan.steps.map((step) => step.toolId),
        capabilityIds: plan.capabilityIds,
        results: [
          const AssistantToolResult(
            toolId: 'yuxiaji_omen',
            title: '玉匣灵兆',
            status: AssistantToolExecutionStatus.noResult,
            values: {'检索状态': 'NO_RESULT'},
          ),
        ],
      );

      final result = HeadlessToolPlanResultHandler.handle(
        userText: '查询玉匣灵兆并抽取三山灵签',
        plan: plan,
        tools: tools,
        execution: execution,
        aiReady: true,
      );

      expect(result.allStepsSucceeded, isFalse);
      expect(result.steps.first.executed, isTrue);
      expect(result.steps.last.executed, isFalse);
      expect(result.responseText, contains('未执行'));
      expect(result.canInterpret, isFalse);
      expect(result.autoInterpret, isFalse);
    });

    test('suppresses invalid result output and refuses aggregate interpretation', () {
      final execution = HeadlessToolPlanExecutionResult(
        planId: plan.planId,
        status: HeadlessToolPlanExecutionStatus.completed,
        toolIds: plan.steps.map((step) => step.toolId),
        capabilityIds: plan.capabilityIds,
        results: [
          const AssistantToolResult(
            toolId: 'dream',
            title: '伪造结果',
            values: {'结果': '不应展示'},
            arguments: {},
            sourceIds: ['local-knowledge:unknown'],
          ),
          const AssistantToolResult(
            toolId: 'sanshan_lingqian',
            title: '三山灵签',
            values: {'签号': '第八签'},
            sourceIds: ['local-knowledge:sanshan'],
            arguments: {},
          ),
        ],
      );

      final result = HeadlessToolPlanResultHandler.handle(
        userText: '查询玉匣灵兆并抽取三山灵签',
        plan: plan,
        tools: tools,
        execution: execution,
        aiReady: true,
      );

      expect(result.contractErrors, isNotEmpty);
      expect(result.responseText, contains('结果不展示'));
      expect(result.responseText, isNot(contains('不应展示')));
      expect(result.canInterpret, isFalse);
      expect(result.autoInterpret, isFalse);
    });
  });
}
