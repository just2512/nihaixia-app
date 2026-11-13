import 'dart:math';

import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import '../data/meihua_data.dart';
import '../models/assistant_tool_result.dart';
import 'bazi_service.dart' show computeBaZiPaipan;

/// Headless adapter for the three calculation methods already implemented by
/// MeihuaScreen. It shares the page's deterministic algorithms and does not
/// create a second set of hexagram, time-conversion, or randomization rules.
class MeihuaToolExecutor {
  static const String sourceId = 'local-engine:meihua';
  static const String dataSourceId = 'local-data:yijing-hexagrams';
  static const List<String> earthlyBranches = [
    '子', '丑', '寅', '卯', '辰', '巳',
    '午', '未', '申', '酉', '戌', '亥',
  ];

  static AssistantToolResult execute(
    Map<String, String> arguments, {
    DateTime? now,
    Random? rng,
  }) {
    const allowedKeys = {
      'method',
      'first',
      'second',
      'date',
      'hour_branch',
    };
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      return _failure(arguments, '包含未声明的起卦参数，未执行计算。');
    }

    final method = arguments['method'];
    if (!const {'number', 'time', 'random'}.contains(method)) {
      return _failure(arguments, '缺少或不支持起卦方式；请选择数字、时间或随机起卦，未执行计算。');
    }

    final clock = now ?? DateTime.now();
    final rawDate = arguments['date'];
    final date = rawDate == null
        ? DateTime(clock.year, clock.month, clock.day)
        : _parseDate(rawDate);
    if (date == null) {
      return _failure(arguments, '起卦日期无效；请使用公历 YYYY-MM-DD，未执行起卦。');
    }
    final lastAllowedDate = DateTime(clock.year, clock.month, clock.day)
        .add(const Duration(days: 365));
    if (date.year < 1920 || date.isAfter(lastAllowedDate)) {
      return _failure(arguments, '起卦日期须在 1920 年至本地今天之后一年内，未执行起卦。');
    }

    // Match MeihuaScreen._compute(): convert the Gregorian date at local noon
    // to a lunar date, avoiding a midnight boundary ambiguity.
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

    final executionArguments = <String, String>{
      'method': method!,
      'date': _formatDate(date),
    };
    late final MeihuaChart chart;
    String? executedHourBranch;

    switch (method) {
      case 'number':
        if (arguments.containsKey('hour_branch')) {
          return _failure(arguments, '数字起卦不接受时辰参数；未执行计算。');
        }
        final first = int.tryParse(arguments['first'] ?? '');
        final second = int.tryParse(arguments['second'] ?? '');
        if (first == null || second == null) {
          return _failure(arguments, '数字起卦缺少两个有效数字；未执行计算。');
        }
        if (first < 1 || first > (1 << 31) ||
            second < 1 || second > (1 << 31)) {
          return _failure(arguments, '两个起卦数字均须为 1 至 ${1 << 31} 的正整数；未执行计算。');
        }
        chart = computeMeihuaByNumber(
          first: first,
          second: second,
          lunarMonth: lunar.month,
        );
        // Keep the exact validated request values in provenance metadata;
        // the displayed calculation values below use parsed integers.
        executionArguments
          ..['first'] = arguments['first']!
          ..['second'] = arguments['second']!;
        break;

      case 'time':
        if (arguments.containsKey('first') || arguments.containsKey('second')) {
          return _failure(arguments, '时间起卦不接受数字起卦参数；未执行计算。');
        }
        // The original page defaults to the device's current local shichen.
        // A supplied branch is validated against the same 12-branch selector.
        final branchIndex = arguments['hour_branch'] == null
            ? _shiChenIndexOfHour(clock.hour)
            : earthlyBranches.indexOf(arguments['hour_branch']!);
        if (branchIndex < 0 || branchIndex >= earthlyBranches.length) {
          return _failure(arguments, '时间起卦时辰无效；请选择十二地支时辰，未执行计算。');
        }
        executedHourBranch = earthlyBranches[branchIndex];
        final pageCompatibleSolar = DateTime(
          date.year,
          date.month,
          date.day,
          branchIndex * 2,
          0,
        );
        final bazi = computeBaZiPaipan(
          pageCompatibleSolar,
          useTrueSolarTime: false,
          ratHourMode: false,
        );
        final yearZhiIndex = _zhiIndex(bazi.zhis[0]);
        final hourZhiIndex = _zhiIndex(bazi.zhis[3]);
        if (yearZhiIndex == null || hourZhiIndex == null) {
          return _failure(arguments, '无法从 App 既有排盘结果读取年月时支；未执行起卦。');
        }
        chart = computeMeihuaByTime(
          yearZhiIndex: yearZhiIndex,
          lunarMonth: lunar.month,
          lunarDay: lunar.day,
          hourZhiIndex: hourZhiIndex,
        );
        executionArguments['hour_branch'] = executedHourBranch;
        break;

      case 'random':
        if (arguments.containsKey('first') ||
            arguments.containsKey('second') ||
            arguments.containsKey('hour_branch')) {
          return _failure(arguments, '随机起卦不接受数字或指定时辰参数；未执行计算。');
        }
        chart = computeMeihuaByRandom(
          lunarMonth: lunar.month,
          rng: rng,
        );
        break;
    }

    return AssistantToolResult(
      toolId: 'meihua',
      title: '梅花易数${chart.methodLabel}',
      values: {
        '起卦方式': chart.methodLabel,
        '公历日期': _formatDate(date),
        '农历月份': '${lunar.month}月',
        if (executedHourBranch != null) '起卦时辰': '${executedHourBranch}时',
        if (method == 'number') '第一数（上卦）': executionArguments['first']!,
        if (method == 'number') '第二数（下卦）': executionArguments['second']!,
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
            .join('\\n'),
        '主断': chart.verdict,
        '推算过程': chart.trace.join('；'),
      },
      sourceIds: const [sourceId, dataSourceId],
      arguments: Map<String, String>.unmodifiable(executionArguments),
      disclaimer: '依据 App 本地梅花易数既有算法及易经卦爻数据生成；仅供传统民俗文化学习参考，不是科学预测或行动指令，不用于医疗、法律或投资决策。',
    );
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'meihua',
        title: '梅花易数起卦',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行起卦。',
      );

  static int? _zhiIndex(String zhi) {
    final index = earthlyBranches.indexOf(zhi);
    return index < 0 ? null : index + 1;
  }

  static int _shiChenIndexOfHour(int hour) =>
      ((hour.clamp(0, 23) + 1) ~/ 2) % 12;

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
