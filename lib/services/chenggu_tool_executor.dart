import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import '../data/chenggu_data.dart';
import '../data/settings_repository.dart';
import '../models/assistant_tool_result.dart';
import 'bazi_service.dart' show computeBaZiPaipan;

/// Reuses the exact Chenggu calculation path from ChengguBoneScreen.
/// User birth details remain explicit; screen sample defaults are never used.
class ChengguToolExecutor {
  static const String sourceId = 'local-engine:chenggu';
  static const String dataSourceId = 'local-data:chenggu-bone-weight';
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
      return _failure(arguments, '包含未声明的称骨参数；本次未执行计算。');
    }
    final date = _parseDate(arguments['birth_date']);
    if (date == null) {
      return _failure(arguments, '出生日期缺失或无效；请提供公历 YYYY-MM-DD。');
    }
    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请提供当地钟表时间 HH:mm。');
    }

    try {
      final settings = SettingsRepository.instance;
      if (!settings.isLoaded) await settings.load();
      await ChengguData.ensureLoaded();

      final solar = DateTime(date.year, date.month, date.day, time.$1, time.$2);
      final useTrueSolarTime = settings.useTrueSolarTime;
      final distinguishZiShi = settings.distinguishZiShiEnabled;
      final chart = computeBaZiPaipan(
        solar,
        useTrueSolarTime: useTrueSolarTime,
        ratHourMode: distinguishZiShi,
      );

      // Match the current page exactly: year Gan-Zhi and calculation hour
      // branch come from the Bazi engine/settings; lunar month/day are based
      // on the entered Gregorian birth date at local noon.
      final yearGanZhi = chart.gans[0] + chart.zhis[0];
      final calculationHourBranch = chart.zhis[3];
      final lunar = LunarDate.fromSolar(
        AstroDateTime(date.year, date.month, date.day, 12, 0, 0),
      );
      final result = ChengguData.compute(
        yearGanZhi,
        lunar.month,
        lunar.day,
        calculationHourBranch,
      );
      final wallClockBranch =
          earthlyBranches[((time.$1.clamp(0, 23) + 1) ~/ 2) % 12];

      final normalizedArguments = <String, String>{
        'birth_date': _formatDate(date),
        'birth_time': _formatTime(time.$1, time.$2),
      };
      return AssistantToolResult(
        toolId: 'chenggu',
        title: '袁天罡称骨',
        values: {
          '出生公历': _formatDate(date) + ' ' + _formatTime(time.$1, time.$2),
          '出生农历口径': yearGanZhi + '年农历' +
              lunar.month.toString() + '月' + lunar.day.toString() + '日',
          '出生钟表时辰': wallClockBranch + '时',
          '称骨计算时柱地支': calculationHourBranch,
          '真太阳时校正': useTrueSolarTime ? '开启' : '关闭',
          '早晚子时区分': distinguishZiShi ? '开启' : '关闭',
          '总骨重': result.liang.toString() + '两' +
              result.qian.toString() + '钱（' +
              result.totalQian.toString() + '钱）',
          '称骨歌诀标题': result.title.isEmpty ? 'MISSING' : result.title,
          '称骨歌诀': result.poem.isEmpty ? 'MISSING' : result.poem,
          '称骨说明': result.detail.isEmpty ? 'MISSING' : result.detail,
        },
        sourceIds: const [sourceId, dataSourceId],
        arguments: Map<String, String>.unmodifiable(normalizedArguments),
        disclaimer: ChengguData.disclaimer.isEmpty
            ? '传统民俗文化参考，非科学预测，不作为生活决策依据。'
            : ChengguData.disclaimer,
      );
    } catch (error) {
      return _failure(arguments, 'App 本地称骨计算未完成：$error');
    }
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'chenggu',
        title: '袁天罡称骨',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验或本地执行未通过；本次未产生称骨结果。',
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
