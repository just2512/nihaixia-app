import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import '../data/huangdi_siji_data.dart';
import '../models/assistant_tool_result.dart';

/// Headless adapter for the existing Huangdi Siji lookup.
///
/// The original page's calculation is authoritative:
/// Gregorian birth date -> lunar month at local noon -> 12-branch clock slot
/// -> HuangdiSijiData.compute. The model never creates or changes this result.
class HuangdiSijiToolExecutor {
  static const String sourceId = 'local-engine:huangdi-siji';
  static const String dataSourceId = 'local-data:huangdi-siji-ge';
  static const List<String> earthlyBranches = [
    '子', '丑', '寅', '卯', '辰', '巳',
    '午', '未', '申', '酉', '戌', '亥',
  ];

  static const Set<String> _allowedArguments = {
    'birth_date',
    'birth_time',
  };

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的黄帝四季歌参数；本次未执行查询。');
    }

    final date = _parseDate(arguments['birth_date']);
    if (date == null) {
      return _failure(arguments, '出生日期缺失或无效；请提供公历 YYYY-MM-DD。');
    }
    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请提供 24 小时制 HH:mm。');
    }

    try {
      await HuangdiSijiData.ensureLoaded();

      // Match HuangdiSijiScreen: lunar month is derived from the entered
      // Gregorian date at local noon; clock hour selects the earthly branch
      // using the existing page formula.
      final lunar = LunarDate.fromSolar(
        AstroDateTime(date.year, date.month, date.day, 12, 0, 0),
      );
      final shiChenIndex = ((time.$1.clamp(0, 23) + 1) ~/ 2) % 12;
      final shiChen = earthlyBranches[shiChenIndex];
      final season = HuangdiSijiData.seasonOfLunarMonth(lunar.month);
      final result = HuangdiSijiData.compute(lunar.month, shiChen);

      final normalizedArguments = <String, String>{
        'birth_date': _formatDate(date),
        'birth_time': _formatTime(time.$1, time.$2),
      };
      return AssistantToolResult(
        toolId: 'huangdi_siji',
        title: '轩辕黄帝四季歌',
        values: {
          '出生公历': _formatDate(date) + ' ' + _formatTime(time.$1, time.$2),
          '农历月份': lunar.month.toString(),
          '季节口径': season,
          '出生时辰': shiChen + '时',
          '对应部位': result.part,
          '命格标题': result.title,
          '部位诗': result.poem,
          '现有释义': result.interpretation,
          '季节边界说明': HuangdiSijiData.seasonBasisNote,
        },
        sourceIds: const [sourceId, dataSourceId],
        arguments: Map<String, String>.unmodifiable(normalizedArguments),
        disclaimer: HuangdiSijiData.disclaimer.isEmpty
            ? '传统民俗文化资料，仅供文化学习参考，不是科学预测或个人决策依据。'
            : HuangdiSijiData.disclaimer,
      );
    } catch (error) {
      return _failure(arguments, 'App 本地黄帝四季歌查询未完成：$error');
    }
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'huangdi_siji',
        title: '轩辕黄帝四季歌',
        values: {'未执行原因': message},
        status: AssistantToolExecutionStatus.failed,
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验或本地数据执行未通过；本次未产生查询结果。',
      );

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    final today = DateTime.now();
    if (parsed.year < 1920 ||
        parsed.isAfter(DateTime(today.year, today.month, today.day))) {
      return null;
    }
    return parsed;
  }

  static (int, int)? _parseTime(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(raw);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static String _formatDate(DateTime date) =>
      date.year.toString().padLeft(4, '0') + '-' +
      date.month.toString().padLeft(2, '0') + '-' +
      date.day.toString().padLeft(2, '0');

  static String _formatTime(int hour, int minute) =>
      hour.toString().padLeft(2, '0') + ':' +
      minute.toString().padLeft(2, '0');
}
