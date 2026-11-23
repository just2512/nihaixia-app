import '../models/tool_execution_plan.dart';
import '../screens/assistant_tool_router.dart';
import 'assistant_conversation_orchestrator.dart';
import 'headless_tool_dispatcher.dart';

/// Result of deterministic plan construction. A failed preflight never
/// exposes a partially constructed plan to the execution layer.
class AssistantToolPlanBuildResult {
  AssistantToolPlanBuildResult({
    required this.plan,
    required Iterable<String> errors,
  })  : errors = List<String>.unmodifiable(errors);

  final ToolExecutionPlan? plan;
  final List<String> errors;

  bool get isValid => plan != null && errors.isEmpty;
}

/// Converts a model-selected ordered list of candidate IDs into a complete
/// immutable execution plan. The model never supplies arguments or capability
/// IDs: both are resolved from the App registry and original user text.
class AssistantToolExecutionPlanBuilder {
  AssistantToolExecutionPlanBuilder._();

  static const int maxSteps = 3;
  static const int maxCandidates = 6;

  static AssistantToolPlanBuildResult build({
    required String planId,
    required String query,
    required List<AssistantToolDefinition> candidates,
    required List<String> orderedToolIds,
  }) {
    final errors = <String>[];
    final normalizedPlanId = planId.trim();
    final normalizedQuery = query.trim();

    if (normalizedPlanId.isEmpty || normalizedPlanId.length > 64) {
      errors.add('计划标识为空或超出长度限制');
    }
    if (normalizedQuery.isEmpty || normalizedQuery.length > 2000) {
      errors.add('计划原始输入为空或超出长度限制');
    }
    if (candidates.length < 2 || candidates.length > maxCandidates) {
      errors.add('候选工具数量必须为 2–$maxCandidates 项');
    }

    final candidateIds = <String>{};
    final candidatesById = <String, AssistantToolDefinition>{};
    for (final tool in candidates) {
      if (tool.id.trim().isEmpty ||
          tool.id != tool.id.trim() ||
          !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(tool.id)) {
        errors.add('候选工具包含无效 ID');
        continue;
      }
      if (!candidateIds.add(tool.id)) {
        errors.add('候选工具 ID 重复：${tool.id}');
        continue;
      }
      candidatesById[tool.id] = tool;
      final registeredCapability =
          HeadlessToolDispatcher.capabilityIdForTool(tool.id);
      if (registeredCapability == null || !HeadlessToolDispatcher.hasExecutor(tool.id)) {
        errors.add('候选工具尚无 Headless 执行器：${tool.id}');
      } else if (registeredCapability != tool.capabilityId) {
        errors.add('候选工具能力元数据与执行器注册不一致：${tool.id}');
      }
    }

    if (orderedToolIds.length < 2 || orderedToolIds.length > maxSteps) {
      errors.add('计划步骤数量必须为 2–$maxSteps 项');
    }
    final selectedIds = <String>{};
    for (final id in orderedToolIds) {
      if (id.trim().isEmpty ||
          id != id.trim() ||
          !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(id)) {
        errors.add('计划包含无效工具 ID');
      }
      if (!selectedIds.add(id)) {
        errors.add('计划重复包含工具：$id');
      }
      if (!candidatesById.containsKey(id)) {
        errors.add('计划工具不在本轮授权候选集合中：$id');
      }
    }

    if (errors.isNotEmpty) {
      return AssistantToolPlanBuildResult(plan: null, errors: errors);
    }

    final steps = <ToolExecutionStep>[];
    for (final id in orderedToolIds) {
      final tool = candidatesById[id]!;
      final arguments =
          AssistantConversationOrchestrator.argumentsFor(tool, normalizedQuery);
      final argumentErrors = arguments.validateAgainst(tool);
      if (argumentErrors.isNotEmpty) {
        errors.addAll(argumentErrors.map((error) => '${tool.title}：$error'));
        continue;
      }
      steps.add(
        ToolExecutionStep(
          toolId: tool.id,
          capabilityId: tool.capabilityId,
          arguments: arguments.values,
        ),
      );
    }

    if (errors.isNotEmpty || steps.length != orderedToolIds.length) {
      return AssistantToolPlanBuildResult(plan: null, errors: errors);
    }

    return AssistantToolPlanBuildResult(
      plan: ToolExecutionPlan(
        planId: normalizedPlanId,
        origin: InvocationOrigin.aiDispatch,
        steps: steps,
      ),
      errors: const [],
    );
  }
}
