import 'dart:async';

import '../models/assistant_tool_result.dart';
import '../models/tool_execution_plan.dart';
import 'yunqi_tool_executor.dart';
import 'ziwei_tool_executor.dart';
import 'bazi_tool_executor.dart';
import 'yijing_tool_executor.dart';
import 'xiaoliuren_tool_executor.dart';
import 'meihua_tool_executor.dart';
import 'dosage_tool_executor.dart';
import 'ziwuliuzhu_tool_executor.dart';
import 'almanac_tool_executor.dart';
import 'solar_term_tool_executor.dart';
import 'yuxiaji_omen_tool_executor.dart';
import 'dream_tool_executor.dart';
import 'guansha_tool_executor.dart';
import 'sanshan_lingqian_tool_executor.dart';
import 'chenggu_tool_executor.dart';
import 'shousheng_debt_tool_executor.dart';
import 'huangdi_siji_tool_executor.dart';
import 'saved_chart_tool_executor.dart';

enum HeadlessToolPlanExecutionStatus {
  completed,
  invalidPlan,
}

/// Immutable result of the whole-plan preflight and dispatch operation.
///
/// Authorization outcomes never contain business results: no step is invoked
/// until every step has been validated and the one plan-level authorization
/// decision (when required) has been allowed.
class HeadlessToolPlanExecutionResult {
  HeadlessToolPlanExecutionResult({
    required this.planId,
    required this.status,
    required Iterable<String> toolIds,
    required Iterable<String> capabilityIds,
    Iterable<AssistantToolResult> results = const [],
    this.offendingToolId,
    this.offendingCapabilityId,
  })  : toolIds = List<String>.unmodifiable(toolIds),
        capabilityIds = Set<String>.unmodifiable(capabilityIds),
        results = List<AssistantToolResult>.unmodifiable(results);

  final String planId;
  final HeadlessToolPlanExecutionStatus status;
  final List<String> toolIds;
  final Set<String> capabilityIds;
  final List<AssistantToolResult> results;
  final String? offendingToolId;
  final String? offendingCapabilityId;

  bool get isCompleted =>
      status == HeadlessToolPlanExecutionStatus.completed;
}

/// The only application boundary that invokes a registered Headless executor.
///
/// Argument collection and validation remain caller responsibilities. The
/// dispatcher validates the complete immutable plan before invoking any step,
/// then executes deterministic business tools in order. It has no license,
/// BuildContext, navigation, trace, persistence, or UI responsibilities.
class HeadlessToolDispatcher {
  const HeadlessToolDispatcher();

  static final Map<String, FutureOr<AssistantToolResult> Function(Map<String, String>)> _executors = {
    'yunqi': YunQiToolExecutor.execute,
    'ziwei': ZiweiToolExecutor.execute,
    'bazi': BaziToolExecutor.execute,
    'yijing': YiJingToolExecutor.execute,
    'xiaoliuren': XiaoliurenToolExecutor.execute,
    'meihua': MeihuaToolExecutor.execute,
    'dosage': DosageToolExecutor.execute,
    'ziwu_liuzhu': ZiWuLiuZhuToolExecutor.execute,
    'almanac': AlmanacToolExecutor.execute,
    'solar_terms': SolarTermToolExecutor.execute,
    'yuxiaji_omen': YuxiajiOmenToolExecutor.execute,
    'dream': DreamToolExecutor.execute,
    'guansha': GuanshaToolExecutor.execute,
    'sanshan_lingqian': SanshanLingqianToolExecutor.execute,
    'chenggu': ChengguToolExecutor.execute,
    'shousheng_debt': ShoushengDebtToolExecutor.execute,
    'huangdi_siji': HuangdiSijiToolExecutor.execute,
    'saved_charts': SavedChartToolExecutor.execute,
  };

  /// Stable capability ownership for registered Headless tool IDs.
  ///
  /// This is intentionally independent of AssistantToolRouter so the business
  /// execution boundary does not import Flutter UI metadata. Registry tests
  /// keep these IDs aligned with AssistantToolDefinition.capabilityId.
  static const Map<String, String> _capabilityIdsByToolId = {
    'yunqi': 'yunqi',
    'ziwei': 'ziwei',
    'bazi': 'bazi',
    'yijing': 'yijing',
    'xiaoliuren': 'xiaoliuren',
    'meihua': 'meihua',
    'dosage': 'dosage',
    'ziwu_liuzhu': 'ziwu_liuzhu',
    'almanac': 'almanac',
    'solar_terms': 'solar_terms',
    'yuxiaji_omen': 'yuxiaji_omen',
    'dream': 'dream',
    'guansha': 'guansha',
    'sanshan_lingqian': 'sanshan_lingqian',
    'chenggu': 'chenggu',
    'shousheng_debt': 'shousheng_debt',
    'huangdi_siji': 'huangdi_siji',
    'saved_charts': 'saved_charts',
  };

  static bool hasExecutor(String toolId) => _executors.containsKey(toolId);

  static String? capabilityIdForTool(String toolId) =>
      _capabilityIdsByToolId[toolId];

  /// Synchronous dispatch for explicitly synchronous context/result adapters.
  ///
  /// These adapters rebuild deterministic local result context; they are not
  /// user tool plans. ContextResolutionGateway separately validates source
  /// references and result anchors.
  /// The allowlist prevents an async executor from being started and abandoned.
  static const Set<String> _synchronousExecutorIds = {
    'dosage',
    'yuxiaji_omen',
  };

  static AssistantToolResult executeSync({
    required String toolId,
    required Map<String, String> arguments,
    DateTime Function()? clock,
  }) {
    if (!_synchronousExecutorIds.contains(toolId)) {
      throw StateError(
        'Tool "${toolId}" is not registered for synchronous dispatch.',
      );
    }
    final executor = _executors[toolId];
    if (executor == null) {
      throw StateError(
        'Tool "${toolId}" does not register a Headless executor.',
      );
    }
    if (clock != null && toolId != 'yuxiaji_omen') {
      throw ArgumentError('A clock override is only supported for yuxiaji_omen.');
    }
    final result = toolId == 'yuxiaji_omen' && clock != null
        ? YuxiajiOmenToolExecutor.execute(arguments, clock: clock)
        : executor(arguments);
    if (result is Future<AssistantToolResult>) {
      throw StateError(
        'Tool "${toolId}" was registered as synchronous but returned a Future.',
      );
    }
    return result;
  }

  /// Validates the entire plan before invoking any executor.
  ///
  /// [executorOverride] is a test seam; it cannot make a Page-only/unregistered
  /// tool executable because the full registry validation happens first.
  Future<HeadlessToolPlanExecutionResult> executePlan({
    required ToolExecutionPlan plan,
    FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
        executorOverride,
  }) async {
    final toolIds = plan.steps.map((step) => step.toolId).toList(growable: false);
    final capabilityIds = plan.capabilityIds;

    // Validate every step before authorization or business execution.
    for (final step in plan.steps) {
      final expectedCapabilityId = _capabilityIdsByToolId[step.toolId];
      if (expectedCapabilityId == null ||
          !_executors.containsKey(step.toolId) ||
          expectedCapabilityId != step.capabilityId) {
        return HeadlessToolPlanExecutionResult(
          planId: plan.planId,
          status: HeadlessToolPlanExecutionStatus.invalidPlan,
          toolIds: toolIds,
          capabilityIds: capabilityIds,
          offendingToolId: step.toolId,
          offendingCapabilityId: step.capabilityId,
        );
      }
    }

    final results = <AssistantToolResult>[];
    for (final step in plan.steps) {
      final executor = executorOverride ?? _executors[step.toolId];
      if (executor == null) {
        // Registry validation above makes this unreachable unless the
        // registry is mutated unexpectedly; fail closed without later steps.
        return HeadlessToolPlanExecutionResult(
          planId: plan.planId,
          status: HeadlessToolPlanExecutionStatus.invalidPlan,
          toolIds: toolIds,
          capabilityIds: capabilityIds,
          results: results,
          offendingToolId: step.toolId,
          offendingCapabilityId: step.capabilityId,
        );
      }
      final result = await executor(step.arguments);
      results.add(result);
      if (result.status != AssistantToolExecutionStatus.succeeded) break;
    }

    return HeadlessToolPlanExecutionResult(
      planId: plan.planId,
      status: HeadlessToolPlanExecutionStatus.completed,
      toolIds: toolIds,
      capabilityIds: capabilityIds,
      results: results,
    );
  }
}
