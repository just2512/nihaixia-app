import 'package:ziwei_core/ziwei_core.dart' show Location;

import '../data/guansha_data.dart' show kGuanshaEntries, kExtShaEntries;
import '../data/settings_repository.dart';
import '../engine/guansha_engine.dart' show GuanshaHit, matchGuansha;
import '../models/assistant_tool_result.dart';
import 'bazi_service.dart' show BaZiPaipan, computeBaZiPaipan;
import 'city_location_service.dart' show CityLocation, CityLocationService;

/// Reuses the App's existing Bazi calculation and 36 + 18 Guansha rules.
///
/// This is a traditional folk-culture lookup, not a child-health assessment,
/// risk prediction, diagnosis, or treatment recommendation.
class GuanshaToolExecutor {
  static const String sourceId = 'local-engine:guansha';
  static const String dataSourceId = 'local-data:guansha';
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
      return _failure(arguments, '包含未声明的关煞参数；本次没有执行排盘或规则匹配。');
    }

    final date = _parseDate(arguments['birth_date']);
    if (date == null) {
      return _failure(arguments, '出生日期缺失或无效；请提供公历 YYYY-MM-DD。');
    }
    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请提供出生地当地钟表时间 HH:mm。');
    }

    final gender = arguments['gender'];
    if (gender != 'male' && gender != 'female') {
      return _failure(arguments, '性别缺失或无效；请明确选择男或女。');
    }
    final isMale = gender == 'male';

    final birthplace = arguments['birthplace']?.trim() ?? '';
    if (birthplace.isEmpty) {
      return _failure(arguments, '出生地点缺失；请提供出生城市或区县。');
    }
    final CityLocation? place;
    try {
      place = await CityLocationService.resolveUnique(birthplace);
    } catch (error) {
      return _failure(arguments, '本地出生地目录读取失败；未执行排盘。' + error.toString());
    }
    if (place == null) {
      return _failure(
        arguments,
        '出生地点“' + birthplace +
            '”无法在本地城市目录中唯一识别；请补充省/州和城市或区县，未使用默认经纬度。',
      );
    }

    try {
      final settings = SettingsRepository.instance;
      if (!settings.isLoaded) await settings.load();
      final solar = DateTime(
        date.year,
        date.month,
        date.day,
        time.$1,
        time.$2,
      );
      final useTrueSolarTime = settings.useTrueSolarTime;
      final distinguishZiShi = settings.distinguishZiShiEnabled;
      final BaZiPaipan paipan = computeBaZiPaipan(
        solar,
        isMale: isMale,
        useTrueSolarTime: useTrueSolarTime,
        ratHourMode: distinguishZiShi,
        location: Location(place.lng, place.lat),
      );
      final hits = matchGuansha(paipan, isMale);
      final pillars = [
        paipan.bazi.year,
        paipan.bazi.month,
        paipan.bazi.day,
        paipan.bazi.time,
      ];
      return AssistantToolResult(
        toolId: 'guansha',
        title: '小儿关煞',
        values: {
          '出生公历': _formatDate(date) + ' ' + _formatTime(time.$1, time.$2),
          '出生地点': place.displayName,
          '出生地坐标': '东经 ' + place.lng.toStringAsFixed(4) +
              '，北纬 ' + place.lat.toStringAsFixed(4) + '（WGS-84）',
          '性别': isMale ? '男' : '女',
          '出生农历': paipan.lunarText,
          '四柱': pillars.join(' '),
          '真太阳时校正': useTrueSolarTime ? '开启' : '关闭',
          '早晚子时区分': distinguishZiShi ? '开启' : '关闭',
          '关煞命中数量': hits.length.toString(),
          '本地规则结果': _formatHits(hits),
          '规则库范围': 'App 本地数据集包含 ' +
              kGuanshaEntries.length.toString() + ' 条关煞和 ' +
              kExtShaEntries.length.toString() +
              ' 条扩展煞；只表示该数据集规则匹配，不代表所有民俗流派。',
        },
        sourceIds: const [sourceId, dataSourceId],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '本结果由 App 原有确定性八字排盘引擎和本地关煞规则表生成，只属于传统民俗文化资料。关煞名称、等级和口诀不代表儿童健康风险、疾病、寿命或现实事件，不是医学诊断或预测；民俗化解说法不能替代医疗。儿童健康问题请咨询正规医疗机构。',
      );
    } catch (error) {
      return _failure(arguments, 'App 本地八字/关煞引擎执行失败：' + error.toString());
    }
  }

  static String _formatHits(List<GuanshaHit> hits) {
    if (hits.isEmpty) return '未命中本地规则库收录的关煞。';
    return hits.map((hit) {
      final entry = hit.entry;
      return [
        entry.name + '（' + entry.severity + '；' + entry.category + '）',
        '确定性规则匹配依据：' + hit.reason,
        if (entry.jue.isNotEmpty) '传统民俗口诀原文：' + entry.jue,
      ].join('\n');
    }).join('\n\n');
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
    final today = DateTime.now();
    if (value.year < 1920 ||
        value.isAfter(DateTime(today.year, today.month, today.day))) {
      return null;
    }
    return value;
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
        toolId: 'guansha',
        title: '小儿关煞',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数或出生地点校验未通过；本次没有执行排盘或规则匹配。',
      );
}
