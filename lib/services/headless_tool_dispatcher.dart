import 'dart:async';

import '../models/assistant_tool_result.dart';
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

/// The only application boundary that invokes a registered Headless executor.
///
/// Argument extraction and validation remain in the caller during F0. The
/// dispatcher deliberately has no BuildContext, navigation, trace, persistence,
/// or UI responsibilities; it only resolves and invokes the executor once.
class HeadlessToolDispatcher {
  const HeadlessToolDispatcher._();

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

  static bool hasExecutor(String toolId) => _executors.containsKey(toolId);

  /// Synchronous dispatch for explicitly synchronous adapters only.
  ///
  /// The allowlist prevents an async executor from being started and then
  /// abandoned by a synchronous caller.
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

  static Future<AssistantToolResult> execute({
    required String toolId,
    required Map<String, String> arguments,
    FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
        executorOverride,
  }) async {
    final executor = executorOverride ?? _executors[toolId];
    if (executor == null) {
      throw StateError(
        'Tool "${toolId}" does not register a Headless executor.',
      );
    }
    return await executor(arguments);
  }
}
