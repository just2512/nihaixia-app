import '../models/assistant_tool_result.dart';
import '../models/tool_execution_plan.dart';
import '../screens/assistant_tool_router.dart';
import 'headless_tool_dispatcher.dart';
import 'headless_tool_result_handler.dart';

class HeadlessToolPlanStepPresentation {
  const HeadlessToolPlanStepPresentation({
    required this.toolId,
    required this.capabilityId,
    required this.arguments,
    required this.result,
    required this.presentation,
    required this.executed,
  });

  final String toolId;
  final String capabilityId;
  final Map<String, String> arguments;
  final AssistantToolResult? result;
  final HeadlessToolResultPresentation? presentation;
  final bool executed;

  List<String> get contractErrors =>
      presentation?.contractErrors ?? const [];
}

/// Plan-level presentation. It never merges unlike business fields into one
/// fabricated result; each deterministic result remains separately identified.
class HeadlessToolPlanPresentation {
  HeadlessToolPlanPresentation({
    required this.steps,
    required this.responseText,
    required Iterable<String> sourceIds,
    required Iterable<String> contractErrors,
    required this.allStepsSucceeded,
    required this.canInterpret,
    required this.autoInterpret,
    required this.interpretationPrompt,
    this.followUp,
  })  : sourceIds = List<String>.unmodifiable(sourceIds.toSet()),
        contractErrors = List<String>.unmodifiable(contractErrors);

  final List<HeadlessToolPlanStepPresentation> steps;
  final String responseText;
  final List<String> sourceIds;
  final List<String> contractErrors;
  final bool allStepsSucceeded;
  final bool canInterpret;
  final bool autoInterpret;
  final String interpretationPrompt;
  final HeadlessToolFollowUpIntent? followUp;
}

/// Builds a single conversation result from a dispatcher result without
/// hiding partial execution, skipped steps, invalid result contracts or source
/// boundaries. It performs no persistence, UI mutation or model invocation.
class HeadlessToolPlanResultHandler {
  const HeadlessToolPlanResultHandler._();

  static HeadlessToolPlanPresentation handle({
    required String userText,
    required ToolExecutionPlan plan,
    required List<AssistantToolDefinition> tools,
    required HeadlessToolPlanExecutionResult execution,
    required bool aiReady,
  }) {
    final toolsById = <String, AssistantToolDefinition>{
      for (final tool in tools) tool.id: tool,
    };
    final presentations = <HeadlessToolPlanStepPresentation>[];
    final errors = <String>[];
    final allSourceIds = <String>[];
    final interpretationPrompts = <String>[];
    HeadlessToolFollowUpIntent? followUp;
    var allSucceeded = execution.isCompleted &&
        execution.results.length == plan.steps.length;

    for (var index = 0; index < plan.steps.length; index++) {
      final step = plan.steps[index];
      if (index >= execution.results.length) {
        allSucceeded = false;
        presentations.add(
          HeadlessToolPlanStepPresentation(
            toolId: step.toolId,
            capabilityId: step.capabilityId,
            arguments: step.arguments,
            result: null,
            presentation: null,
            executed: false,
          ),
        );
        continue;
      }

      final result = execution.results[index];
      final tool = toolsById[step.toolId];
      if (tool == null) {
        allSucceeded = false;
        errors.add('计划工具定义缺失：${step.toolId}');
        presentations.add(
          HeadlessToolPlanStepPresentation(
            toolId: step.toolId,
            capabilityId: step.capabilityId,
            arguments: step.arguments,
            result: result,
            presentation: null,
            executed: true,
          ),
        );
        continue;
      }

      final presentation = HeadlessToolResultHandler.handle(
        userText: userText,
        toolId: step.toolId,
        toolTitle: tool.title,
        expectedArguments: step.arguments,
        result: result,
        aiReady: aiReady,
      );
      if (presentation.contractErrors.isNotEmpty) {
        allSucceeded = false;
        errors.addAll(
          presentation.contractErrors.map(
            (error) => '${tool.title}：$error',
          ),
        );
      } else {
        allSourceIds.addAll(presentation.sourceIds);
        if (presentation.canInterpret) {
          interpretationPrompts.add(
            '【${tool.title}】\n${presentation.interpretationPrompt}',
          );
        }
        followUp ??= presentation.followUp;
      }
      if (result.status != AssistantToolExecutionStatus.succeeded) {
        allSucceeded = false;
      }
      presentations.add(
        HeadlessToolPlanStepPresentation(
          toolId: step.toolId,
          capabilityId: step.capabilityId,
          arguments: step.arguments,
          result: result,
          presentation: presentation,
          executed: true,
        ),
      );
    }

    final responseLines = <String>[
      '【AI 多工具计划：${plan.planId}】',
      for (final step in presentations) ...[
        if (!step.executed)
          '【${toolsById[step.toolId]?.title ?? step.toolId}】未执行：前序步骤未成功完成。',
        if (step.executed && step.presentation == null)
          '【${step.toolId}】结果无法关联到已验证的工具定义；结果不展示。',
        if (step.executed && step.contractErrors.isNotEmpty)
          '【${toolsById[step.toolId]?.title ?? step.toolId}】结果契约校验失败：${step.contractErrors.join('；')}。结果不展示，也不会交给 AI 解读。',
        if (step.executed &&
            step.presentation != null &&
            step.contractErrors.isEmpty)
          step.presentation!.responseText,
      ],
      if (!allSucceeded)
        '计划未全部完成。上面逐项标记实际执行结果；未执行步骤没有产生结果。',
      if (errors.isNotEmpty)
        '结果校验问题：${errors.join('；')}',
    ];

    final allCanInterpret = allSucceeded &&
        errors.isEmpty &&
        presentations.length == plan.steps.length &&
        presentations.every(
          (step) => step.presentation?.canInterpret == true,
        );
    final canInterpret = allCanInterpret && interpretationPrompts.isNotEmpty;
    final autoInterpret = canInterpret && aiReady;
    final prompt = [
      '请按原计划顺序分别解释以下已通过结果契约校验的 App 本地工具输出。',
      '不得把不同工具的字段合并为一个结论；逐项标明工具、输入、输出、来源和限制。',
      '任何缺失字段标记 MISSING，不重新计算、不推测前序结果、不把工具输出变成未经验证的因果关系。',
      ...interpretationPrompts,
    ].join('\n\n');

    return HeadlessToolPlanPresentation(
      steps: List<HeadlessToolPlanStepPresentation>.unmodifiable(presentations),
      responseText: responseLines.join('\n\n'),
      sourceIds: allSourceIds,
      contractErrors: errors,
      allStepsSucceeded: allSucceeded && errors.isEmpty,
      canInterpret,
      autoInterpret,
      interpretationPrompt: canInterpret ? prompt : '',
      followUp: followUp,
    );
  }
}
