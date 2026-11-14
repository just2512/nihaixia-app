import 'package:ziwei_core/ziwei_core.dart' show Location;

import '../data/settings_repository.dart';
import '../engine/guansha_engine.dart' show GuanshaHit, matchGuansha;
import '../models/assistant_tool_result.dart';
import 'bazi_service.dart' show computeBaZiPaipan;
import 'bazi_tool_executor.dart' show BaziToolExecutor;

/// Headless adapter for the existing Guansha calculation.
///
/// The adapter uses the same Bazi chart engine, saved solar-time settings and
/// strict city resolver as the existing page. It never uses the page's sample
/// birth date, time, gender or fallback location.
class GuanshaToolExecutor {
  static const String sourceId = 'local-engine:guansha';
  static const String dataSourceId = 'local-data:guansha';
  static const String locationSourceId = 'local-data:city-locations';

  static const Set<String> _allowedArguments = {
    'birth_date',
    'birth_time',
    'gender',
    'birthplace',
  };

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的参数；本次没有执行测算。');
    }

    final date = _parseDate(arguments['birth_date']);
    if (date == null) {
      return _failure(arguments, '出生公历日期缺失或无效；请使用 YYYY-MM-DD。');
    }
    final now = DateTime.now();
    if (date.isBefore(DateTime(1920)) ||
        date.isAfter(DateTime(now.year, now.month, now.day))) {
      return _failure(arguments, '出生日期超出原页面支持范围（1920 年至今天）；本次没有执行测算。');
    }

    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请使用 24 小时制 HH:mm。');
    }

    final gender = arguments['gender'];
    if (gender != 'male' && gender != 'female') {
      return _failure(arguments, '性别缺失或无效；请明确提供男或女。');
    }

    final birthplace = arguments['birthplace']?.trim() ?? '';
    if (birthplace.isEmpty) {
      return _failure(arguments, '出生地点缺失；请提供可唯一识别的城市或区县。');
    }

    final place = await BaziToolExecutor.resolveBirthplace(birthplace);
    if (place == null) {
      return _failure(
        arguments,
        '本地城市目录无法唯一识别「$birthplace」。请补充省/州及城市/区县；本次未使用默认经纬度，也未执行测算。',
      );
    }

    try {
      final settings = SettingsRepository.instance;
      final isMale = gender == 'male';
      final solar = DateTime(date.year, date.month, date.day, time.$1, time.$2);
      final location = Location(place.lng, place.lat);
      final useTrueSolarTime = settings.useTrueSolarTime;
      final distinguishZiShi = settings.distinguishZiShiEnabled;

      // Keep the same inputs and defaults as GuanshaScreen._compute().
      final chart = computeBaZiPaipan(
        solar,
        isMale: isMale,
        useTrueSolarTime: useTrueSolarTime,
        ratHourMode: distinguishZiShi,
        location: location,
      );
      final hits = matchGuansha(chart, isMale);
      final pillars = [
        chart.bazi.year,
        chart.bazi.month,
        chart.bazi.day,
        chart.bazi.time,
      ];
      final hitText = hits.isEmpty
          ? '未命中本地规则库收录的关煞。'
          : hits.map(_formatHit).join('\n\n');

      return AssistantToolResult(
        toolId: 'guansha',
        title: '小儿关煞',
        values: {
          '出生公历': _formatDateTime(solar),
          '性别': isMale ? '男' : '女',
          '出生地点': place.displayName,
          '出生地坐标':
              '东经 ${place.lng.toStringAsFixed(4)}，北纬 ${place.lat.toStringAsFixed(4)}',
          '出生农历': chart.lunarText,
          '四柱': pillars.join(' '),
          '真太阳时校正': useTrueSolarTime ? '开启' : '关闭',
          '早晚子时区分': distinguishZiShi ? '开启' : '关闭',
          '关煞命中数量': hits.length.toString(),
          '本地规则结果': hitText,
          '规则库范围': '本地数据集收录的 36 关与 18 条扩展煞；不代表所有民俗流派。',
        },
        sourceIds: const [sourceId, dataSourceId, locationSourceId],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '传统民俗文化参考，非医学结论；命中内容不代表儿童存在疾病、健康风险或未来事件。不得将关煞名称、儿童身体部位或化解说法解释为健康诊断、治疗或用药建议，也不得据此延误就医。涉及儿童健康问题应以正规医疗机构评估为准。',
      );
    } catch (error) {
      return _failure(arguments, 'App 本地关煞规则执行失败：$error');
    }
  }

  static String _formatHit(GuanshaHit hit) {
    final entry = hit.entry;
    return [
      '${entry.name}（${entry.severity}；${entry.category}）',
      '判定原因：${hit.reason}',
      if (entry.jue.isNotEmpty) '口诀：${entry.jue}',
      if (entry.fanZheJi.isNotEmpty)
        '条目所载犯者忌：${entry.fanZheJi.join('；')}',
      if (entry.huaJie.isNotEmpty)
        '条目所载民俗化解：${entry.huaJie.join('；')}',
    ].join('\n');
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
  }

  static (int, int)? _parseTime(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return (hour, minute);
  }

  static String _formatDateTime(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'guansha',
        title: '小儿关煞',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过或地点无法确认；本次没有执行测算。',
      );
}
