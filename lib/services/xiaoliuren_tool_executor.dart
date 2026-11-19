import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import '../data/xiaoliuren_data.dart';
import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';

class XiaoliurenToolExecution {
  const XiaoliurenToolExecution({
    required this.result,
    this.chart,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final XiaoliurenChart? chart;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      chart != null &&
      structuredSnapshot != null;
}

/// Headless adapter for the existing deterministic Xiaoliuren rule function.
///
/// It preserves both existing rule traditions and records the exact input,
/// lunar conversion, palace hits, rule data and verses in an immutable digest.
class XiaoliurenToolExecutor {
  static const String sourceId = 'local-engine:xiaoliuren';
  static const String ruleDataSourceId = 'local-data:xiaoliuren-rule-data';
  static const String resultSchemaVersion =
      'xiaoliuren-structured-result-v1';
  static const String ruleVersion =
      'xiaoliuren-engine@1;'
      'xiaoliuren-data@43d61af393599582b541c3347815c1034c1f4848;'
      'sxwnl_spa_dart@0.18.5';

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

  /// Backward-compatible result-only API.
  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    return executeWithSnapshot(arguments).result;
  }

  /// Executes the same page calculation and returns its immutable context.
  ///
  /// [now] is injectable for deterministic tests and is stored as the
  /// execution date so a historical snapshot can later be revalidated.
  static XiaoliurenToolExecution executeWithSnapshot(
    Map<String, String> arguments, {
    DateTime? now,
  }) {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failedExecution(arguments, '包含未声明的小六壬参数，本次未执行。');
    }

    final date = _parseDate(arguments['date']);
    if (date == null) {
      return _failedExecution(arguments, '缺少或无法识别公历日期；请使用 YYYY-MM-DD。');
    }

    final hour = arguments['hour']?.trim();
    if (hour == null || !hourBranches.contains(hour)) {
      return _failedExecution(arguments, '缺少或无法识别时辰；请明确提供子时至亥时之一。');
    }

    final ruleValue = arguments['rule']?.trim();
    if (ruleValue == null || ruleValue.isEmpty) {
      return _failedExecution(
        arguments,
        '缺少起课口径；请明确选择通行掌诀或《多能鄙事》卷八口径。',
      );
    }
    final rule = switch (ruleValue) {
      'common' => XiaoliurenRule.common,
      'duoneng' => XiaoliurenRule.duoneng,
      _ => null,
    };
    if (rule == null) {
      return _failedExecution(arguments, '起课口径无效；仅支持 common 或 duoneng。');
    }

    final clock = now ?? DateTime.now();
    final executionDate = DateTime(clock.year, clock.month, clock.day);
    final firstSupportedDate = DateTime(1920);
    final lastSupportedDate =
        executionDate.add(const Duration(days: 365));
    if (date.isBefore(firstSupportedDate) || date.isAfter(lastSupportedDate)) {
      return _failedExecution(
        arguments,
        '公历日期超出页面支持范围（1920 年至今天后 365 天），本次未执行。',
      );
    }

    try {
      // Match XiaoliurenScreen exactly: convert the selected Gregorian date
      // at local noon, then call the one existing pure calculation function.
      final dateText = _formatDate(date);
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
      final executionArguments = Map<String, String>.unmodifiable({
        'date': dateText,
        'hour': hour,
        'rule': ruleValue,
      });

      final monthVerse = xiaoliurenVerse(chart.month.palace, rule);
      final dayVerse = xiaoliurenVerse(chart.day.palace, rule);
      final hourVerse = xiaoliurenVerse(chart.hour.palace, rule);
      const disclaimer =
          '本结果由 App 现有小六壬纯函数按所选口径计算，歌诀来自 App 内置传统资料。'
          '小六壬属于民俗文化参考，不是事实预测或吉凶指令，不用于医疗、法律、投资或其他重要决策。';

      final assistantResult = AssistantToolResult(
        toolId: 'xiaoliuren',
        title: '小六壬起课',
        values: {
          '公历日期': dateText,
          '农历月日': '${chart.lunarMonth}月${chart.lunarDay}日',
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
        arguments: executionArguments,
        disclaimer: disclaimer,
      );

      final monthSteps = chart.lunarMonth - 1;
      final daySteps =
          chart.lunarMonth + chart.lunarDay - 2 + rule.dayStartOffset;
      final hourSteps =
          chart.lunarMonth + chart.lunarDay + chart.hourNumber - 3 +
              rule.dayStartOffset;
      final snapshotBase = <String, Object?>{
        'capabilityId': 'xiaoliuren',
        'resultSchemaVersion': resultSchemaVersion,
        'executionStatus': 'SUCCESS',
        'sourceIds': const [sourceId, ruleDataSourceId],
        'input': <String, Object?>{
          'method': 'time',
          'executionDate': _formatDate(executionDate),
          'arguments': executionArguments,
          'inputConvention':
              '公历日期按本地正午换算农历；用户明确选择子时至亥时及一种既有起课口径；'
              '不从页面显示摘要反推输入。',
          'derived': <String, Object?>{
            'solarNoon': '${dateText}T12:00:00',
            'lunarMonth': chart.lunarMonth,
            'lunarDay': chart.lunarDay,
            'hourNumber': chart.hourNumber,
            'dayStartOffset': rule.dayStartOffset,
          },
        },
        'result': <String, Object?>{
          'lunarMonth': chart.lunarMonth,
          'lunarDay': chart.lunarDay,
          'hourNumber': chart.hourNumber,
          'rule': <String, Object?>{
            'id': rule.name,
            'label': rule.label,
            'source': rule.source,
            'dayStartOffset': rule.dayStartOffset,
          },
          'month': _serializeHit(chart.month, verse: monthVerse),
          'day': _serializeHit(chart.day, verse: dayVerse),
          'hour': _serializeHit(chart.hour, verse: hourVerse),
          'palaceOrder': [
            for (final palace in kXiaoliurenPalaceOrder)
              <String, Object?>{
                'id': palace.index.toString(),
                'name': palace.name,
                'deity': palace.deity,
                'verse': xiaoliurenVerse(palace, rule),
              },
          ],
          'calculationSteps': <String, Object?>{
            'monthSteps': monthSteps,
            'daySteps': daySteps,
            'hourSteps': hourSteps,
          },
        },
        'units': const <String, Object?>{
          'hourNumber': '时辰数：子=1，丑=2，…，亥=12。',
          'steps': '从既定起算宫开始的顺数步数，不换算为概率。',
          'palaceOrder': 'App 内置六宫固定顺序：大安、留连、速喜、赤口、小吉、空亡。',
        },
        'missingFields': const <String>[],
        'displaySummary': <String, Object?>{
          'title': assistantResult.title,
          'values': Map<String, String>.unmodifiable(assistantResult.values),
          'disclaimer': disclaimer,
        },
        'ruleVersion': ruleVersion,
      };
      final snapshotId =
          AiToolResultSnapshot.createStructuredId(snapshot: snapshotBase);
      final snapshot = Map<String, Object?>.unmodifiable({
        ...snapshotBase,
        'snapshotId': snapshotId,
      });

      return XiaoliurenToolExecution(
        result: assistantResult,
        chart: chart,
        structuredSnapshot: snapshot,
      );
    } catch (error) {
      return _failedExecution(arguments, 'App 小六壬排课执行失败：$error');
    }
  }

  static Map<String, Object?> _serializeHit(
    XiaoliurenHit hit, {
    required String verse,
  }) =>
      <String, Object?>{
        'index': hit.index,
        'steps': hit.steps,
        'palace': <String, Object?>{
          'id': hit.palace.index.toString(),
          'name': hit.palace.name,
          'deity': hit.palace.deity,
        },
        'verse': verse,
      };

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
        .firstMatch(normalized);
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

  static XiaoliurenToolExecution _failedExecution(
    Map<String, String> arguments,
    String reason,
  ) {
    final result = AssistantToolResult(
      toolId: 'xiaoliuren',
      title: '小六壬起课',
      status: AssistantToolExecutionStatus.failed,
      values: {'未执行原因': reason},
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '参数或日期范围校验未通过；本次未执行小六壬起课。',
    );
    return XiaoliurenToolExecution(result: result);
  }
}
