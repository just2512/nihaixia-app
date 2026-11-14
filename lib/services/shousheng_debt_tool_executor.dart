import 'dart:convert';

import '../data/settings_repository.dart';
import '../data/shousheng_data.dart';
import '../models/assistant_tool_result.dart';
import 'bazi_service.dart' show computeBaZiPaipan;

/// Headless adapter for the existing Shousheng lookup page.
///
/// The user must explicitly choose the source system. All charting and table
/// lookups reuse the existing App functions and bundled data; no page defaults
/// are used as conversation inputs.
class ShoushengDebtToolExecutor {
  static const String sourceId = 'local-engine:shousheng_debt';
  static const String lukuDataSourceId = 'local-data:luku-shousheng-debt';
  static const String wudouDataSourceId = 'local-data:wudou-shousheng-debt';

  static const List<String> methods = ['luku', 'wudou'];

  static const Set<String> _allowedArguments = {
    'birth_date',
    'birth_time',
    'method',
  };

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的受生债查询参数；本次未执行。');
    }

    final date = _parseDate(arguments['birth_date']);
    if (date == null) {
      return _failure(arguments, '出生日期缺失或无效；请提供公历 YYYY-MM-DD。');
    }
    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请提供当地钟表时间 HH:mm。');
    }
    final method = arguments['method'];
    if (!methods.contains(method)) {
      return _failure(
        arguments,
        '查询体系未明确或无效；请明确选择「禄库受生经」或「五斗金章受生经」。',
      );
    }

    try {
      final settings = SettingsRepository.instance;
      if (!settings.isLoaded) await settings.load();
      await ShoushengData.ensureLoaded();

      final solar = DateTime(date.year, date.month, date.day, time.$1, time.$2);
      // Match ShoushengDebtScreen._compute exactly. The page intentionally
      // has no gender or birth-location input for this lookup.
      final chart = computeBaZiPaipan(
        solar,
        useTrueSolarTime: settings.useTrueSolarTime,
        ratHourMode: settings.distinguishZiShiEnabled,
      );
      final yearZhi = chart.zhis[0];
      final dayGan = chart.gans[2];
      final timeZhi = chart.zhis[3];

      final values = <String, String>{
        '出生公历': '${_formatDate(date)} ${_formatTime(time.$1, time.$2)}',
        '查询体系': method == 'luku' ? '禄库受生经' : '五斗金章受生经',
        '年支': yearZhi,
        '日干': dayGan,
        '时支': timeZhi,
        '真太阳时校正': settings.useTrueSolarTime ? '开启' : '关闭',
        '早晚子时区分': settings.distinguishZiShiEnabled ? '开启' : '关闭',
      };
      final sourceIds = <String>[sourceId];

      String disclaimer;
      if (method == 'luku') {
        final result = ShoushengData.computeLuku(yearZhi);
        if (result.warehouse.isEmpty || result.yuanchen.isEmpty) {
          throw StateError('禄库受生经数据缺失；未形成可解释结果。');
        }
        disclaimer = ShoushengData.lukuDisclaimer;
        if (disclaimer.trim().isEmpty) {
          throw StateError('禄库受生经数据缺少用途声明；未形成可解释结果。');
        }
        values
          ..['禄库曹官数据'] = jsonEncode(result.warehouse)
          ..['本命元辰数据'] = jsonEncode(result.yuanchen);
        sourceIds.add(lukuDataSourceId);
      } else {
        final result = ShoushengData.computeWudou(dayGan, timeZhi);
        if (result.fiveDou.isEmpty || result.kushen.isEmpty) {
          throw StateError('五斗金章受生经数据缺失；未形成可解释结果。');
        }
        disclaimer = ShoushengData.wudouDisclaimer;
        if (disclaimer.trim().isEmpty || ShoushengData.wudouNote.trim().isEmpty) {
          throw StateError('五斗金章受生经数据缺少用途声明或口径说明；未形成可解释结果。');
        }
        values
          ..['五斗本命钱数据'] = jsonEncode(result.fiveDou)
          ..['十二库神数据'] = jsonEncode(result.kushen)
          ..['口径说明'] = ShoushengData.wudouNote;
        sourceIds.add(wudouDataSourceId);
      }

      final normalizedArguments = <String, String>{
        'birth_date': _formatDate(date),
        'birth_time': _formatTime(time.$1, time.$2),
        'method': method!,
      };
      return AssistantToolResult(
        toolId: 'shousheng_debt',
        title: '受生债查询',
        values: values,
        sourceIds: List.unmodifiable(sourceIds),
        arguments: Map.unmodifiable(normalizedArguments),
        disclaimer: disclaimer,
      );
    } catch (error) {
      return _failure(arguments, 'App 原有受生债查询未完成：$error');
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
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    final today = DateTime.now();
    if (year < 1920 ||
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

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'shousheng_debt',
        title: '受生债查询',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map.unmodifiable(arguments),
        disclaimer: '参数校验或本地数据执行未通过；本次没有产生查询结果。',
      );
}
