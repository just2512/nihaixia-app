import '../models/assistant_tool_result.dart';
import 'lunar_almanac_service.dart';

/// Synchronous, side-effect-free Headless adapter for the existing local
/// almanac calculation. It does not read saved charts or personal profile data.
class AlmanacToolExecutor {
  static const String sourceId = 'local-engine:almanac';

  static AssistantToolResult execute(Map<String, String> arguments) {
    if (arguments.keys.any((key) => key != 'date')) {
      return _failure(arguments, '包含未声明的查询参数，未执行计算。');
    }

    final rawDate = arguments['date'];
    final date = rawDate == null ? null : _parseDate(rawDate);
    if (date == null) {
      return _failure(arguments, '查询日期无效；请使用 YYYY-MM-DD，未执行计算。');
    }
    if (date.year < 1900 || date.year > 2100) {
      return _failure(arguments, '查询日期超出支持范围（1900-2100），未执行计算。');
    }

    final day = getDailyAlmanac(date);
    return AssistantToolResult(
      toolId: 'almanac',
      title: '每日黄历',
      values: {
        '公历': _formatDate(day.solar),
        '星期': day.weekdayName,
        '农历': day.lunarText,
        '干支': '${day.ganzhiYear}年 ${day.ganzhiMonth}月 ${day.ganzhiDay}日',
        '建除': day.jianChu,
        '彭祖百忌': day.pengZu.join('；'),
        '冲煞': '${day.chong}，${day.sha}',
        '日生肖': day.dayZodiac,
        '宜': day.yi.join('、'),
        '忌': day.ji.join('、'),
        '黄道吉时': day.jiShi.join('、'),
        '财神方位': day.caiShen,
        '喜神方位': day.xiShen,
        '福神方位': day.fuShen,
        '节气': day.solarTerm ?? '当日无交节',
        '节日': [
          ...day.festivals,
          ...day.deityFestivals,
          ...day.chaoshanFestivals,
        ].join('、'),
      },
      sourceIds: const [sourceId],
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '依据 App 本地历法与通胜规则计算，仅作传统民俗文化参考；不是事实预测或行为指令，不构成医疗、法律或投资建议。',
    );
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'almanac',
        title: '每日黄历',
        status: AssistantToolExecutionStatus.failed,
        values: {'错误': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '本次没有执行黄历计算。',
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
