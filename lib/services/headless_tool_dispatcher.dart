import 'dart:async';

import '../models/assistant_tool_result.dart';
import '../screens/assistant_tool_router.dart';
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

  static Future<AssistantToolResult> execute({
    required AssistantToolDefinition tool,
    required Map<String, String> arguments,
    FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
        executorOverride,
  }) async {
    final executor = executorOverride ?? _executors[tool.id];
    if (executor == null) {
      throw StateError(
        'Tool "${tool.id}" does not register a Headless executor.',
      );
    }
    return await executor(arguments);
  }
}
