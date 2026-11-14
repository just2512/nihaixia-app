import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart' show AstroDateTime, LunarDate;

import '../data/xiaoliuren_data.dart';
import '../models/assistant_tool_result.dart';

/// Headless adapter for the existing Xiaoliuren deterministic rule function.
///
/// It keeps the same Gregorian-noon -> LunarDate conversion as the original
/// page, preserves both existing rule traditions and never invents a result.
class XiaoliurenToolExecutor {
  static const String sourceId = 'local-engine:xiaoliuren';
  static const String ruleDataSourceId = 'local-data:xiaoliuren-rule-data';

  static const List<String> hourBranches = [
    '子时',
    '丑时',
    '寅时',
    '卯时',
    '辰时',
    '巳时',
    '午时',
    '未时',
    '申时',
    '酉时',
    '戌时',
    '亥时',
  ];

  static const Set<String> _allowedArguments = {'date', 'hour', 'rule'};

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的小六壬参数，本次未执行。');
    }

    final date = _parseDate(arguments['date']);
    if (date == null) {
      return _failure(arguments, '缺少或无法识别公历日期；请使用 YYYY-MM-DD。');
    }

    final hour = arguments['hour']?.trim();
    if (hour == null || !hourBranches.contains(hour)) {
      return _failure(arguments, '缺少或无法识别时辰；请明确提供子时至亥时之一。');
    }

    final ruleValue = arguments['rule']?.trim().isNotEmpty == true
        ? arguments['rule']!.trim()
        : 'common';
    final rule = switch (ruleValue) {
      'common' => XiaoliurenRule.common,
      'duoneng' => XiaoliurenRule.duoneng,
      _ => null,
    };
    if (rule == null) {
      return _failure(arguments, '起课口径无效；仅支持 common 或 duoneng。');
    }

    final today = DateTime.now();
    final firstSupportedDate = DateTime(1920);
    final lastSupportedDate =
        DateTime(today.year, today.month, today.day).add(const Duration(days: 365));
    if (date.isBefore(firstSupportedDate) || date.isAfter(lastSupportedDate)) {
      return _failure(
        arguments,
        '公历日期超出页面支持范围（1920 年至今天后 365 天），本次未执行。',
      );
    }

    try {
      // Match XiaoliurenScreen exactly: convert the selected Gregorian date
      // at local noon, then use the App's existing LunarDate implementation.
      final lunar = LunarDate.fromSolar(
        AstroDateTime(date.year, date.month, date.day, 12, 0, 0),
      );
      final hourNumber = hourBranches.indexOf(hour) + 1;
      final chart = computeXiaoliuren(
        lunarMonth: lunar.month,
        lunarDay: lunar.day,
        hourNumber: hourNumber,
        rule: rule,
      );
      final dateText = _formatDate(date);
      final lunarDateText = '${chart.lunarMonth}月${chart.lunarDay}日';
      final monthVerse = xiaoliurenVerse(chart.month.palace, rule);
      final dayVerse = xiaoliurenVerse(chart.day.palace, rule);
      final hourVerse = xiaoliurenVerse(chart.hour.palace, rule);

      return AssistantToolResult(
        toolId: 'xiaoliuren',
        title: '小六壬起课',
        values: {
          '公历日期': dateText,
          '农历月日': lunarDateText,
          '时辰': hour,
          '起课口径': rule.label,
          '口径说明': rule.source,
          '月宫': chart.month.palace.name,
          '月宫主事': chart.month.palace.deity,
          '月宫顺数步数': chart.month.steps.toString(),
          '月宫歌诀': monthVerse,
          '日宫': chart.day.palace.name,
          '日宫主事': chart.day.palace.deity,
          '日宫顺数步数': chart.day.steps.toString(),
          '日宫歌诀': dayVerse,
          '正时主断': chart.hour.palace.name,
          '正时主事': chart.hour.palace.deity,
          '正时顺数步数': chart.hour.steps.toString(),
          '正时歌诀': hourVerse,
          '排课顺序': '农历月定月宫；农历日定日宫；所选时辰定正时主断。',
        },
        sourceIds: const [sourceId, ruleDataSourceId],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '本结果由 App 现有小六壬纯函数按所选口径计算，歌诀来自 App 内置传统资料。小六壬属于民俗文化参考，不是事实预测或吉凶指令，不用于医疗、法律、投资或其他重要决策。',
      );
    } catch (error) {
      return _failure(arguments, 'App 小六壬排课执行失败：$error');
    }
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'xiaoliuren',
        title: '小六壬起课',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数或日期范围校验未通过；本次未执行小六壬起课。',
      );
}
