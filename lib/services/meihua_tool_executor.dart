import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import '../data/meihua_data.dart';
import '../models/assistant_tool_result.dart';

/// Headless adapter for the existing numeric Meihua calculation.
///
/// Only the App's deterministic number method is supported here. Time-based
/// and random methods stay on the existing page because they have different
/// input semantics (birth-time conversion and entropy, respectively).
class MeihuaToolExecutor {
  static const String sourceId = 'local-engine:meihua';
  static const String dataSourceId = 'local-data:yijing-hexagrams';

  static AssistantToolResult execute(
    Map<String, String> arguments, {
    DateTime? now,
  }) {
    const allowedKeys = {'first', 'second', 'date'};
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      return _failure(arguments, '包含未声明的起卦参数，未执行计算。');
    }

    final first = int.tryParse(arguments['first'] ?? '');
    final second = int.tryParse(arguments['second'] ?? '');
    if (first == null || second == null) {
      return _failure(arguments, '缺少两个有效数字；未执行起卦。');
    }
    if (first < 1 || first > (1 << 31) ||
        second < 1 || second > (1 << 31)) {
      return _failure(arguments, '两个起卦数字均须为 1 至 ${1 << 31} 的正整数；未执行起卦。');
    }

    final rawDate = arguments['date'];
    final date = rawDate == null ? null : _parseDate(rawDate);
    if (date == null) {
      return _failure(arguments, '起卦日期无效；请使用公历 YYYY-MM-DD，未执行起卦。');
    }
    final clock = now ?? DateTime.now();
    final lastAllowedDate = DateTime(clock.year, clock.month, clock.day)
        .add(const Duration(days: 365));
    if (date.year < 1920 || date.isAfter(lastAllowedDate)) {
      return _failure(arguments, '起卦日期须在 1920 年至本地今天之后一年内，未执行起卦。');
    }

    // Match MeihuaScreen._compute(): use the Gregorian date at local noon
    // for lunar-month conversion, avoiding a midnight boundary ambiguity.
    final solarNoon = DateTime(date.year, date.month, date.day, 12);
    final lunar = LunarDate.fromSolar(
      AstroDateTime(
        solarNoon.year,
        solarNoon.month,
        solarNoon.day,
        12,
        0,
      ),
    );
    final chart = computeMeihuaByNumber(
      first: first,
      second: second,
      lunarMonth: lunar.month,
    );

    return AssistantToolResult(
      toolId: 'meihua',
      title: '梅花易数数字起卦',
      values: {
        '起卦方式': chart.methodLabel,
        '公历日期': _formatDate(date),
        '农历月份': '${lunar.month}月',
        '第一数（上卦）': '$first',
        '第二数（下卦）': '$second',
        '主卦': '第${chart.main.seq}卦 ${chart.main.name}',
        '主卦卦辞': chart.main.judgement,
        '互卦': '第${chart.mutual.seq}卦 ${chart.mutual.name}',
        '变卦': '第${chart.changed.seq}卦 ${chart.changed.name}',
        '动爻': '第${chart.movingYao}爻',
        '动爻爻辞': chart.movingYaoCi,
        '体卦': '${chart.ti.name}（${chart.tiWuxing}）',
        '用卦': '${chart.yong.name}（${chart.yongWuxing}）',
        '体用关系': chart.mainRelation.label,
        '月令': chart.monthBranch,
        '体卦旺衰': chart.tiWangShuai.label,
        '三阶段推演': chart.stages
            .map((stage) => '${stage.name}：${stage.hexName}；${stage.detail}')
            .join('\n'),
        '主断': chart.verdict,
        '推算过程': chart.trace.join('；'),
      },
      sourceIds: const [sourceId, dataSourceId],
      arguments: Map<String, String>.unmodifiable({
        'first': '$first',
        'second': '$second',
        'date': _formatDate(date),
      }),
      disclaimer: '依据 App 本地梅花易数数字起卦算法及易经卦爻数据生成；仅供传统民俗文化学习参考，不是科学预测或行动指令，不用于医疗、法律或投资决策。',
    );
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'meihua',
        title: '梅花易数数字起卦',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行起卦。',
      );

  static DateTime? _parseDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || _formatDate(parsed) != raw) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
