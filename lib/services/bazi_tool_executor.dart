import 'package:ziwei_core/ziwei_core.dart' show Location;

import '../data/settings_repository.dart';
import '../engine/bazi_twelve_stages.dart' show TwelveStageMode;
import '../models/assistant_tool_result.dart';
import 'assistant_chart_result_formatter.dart';
import 'bazi_service.dart';
import 'city_location_service.dart';

/// Headless adapter for the existing deterministic Bazi calculation.
///
/// It reuses the same calculation functions and preferences as
/// BaZiPaipanScreen. All birth details are explicit; this adapter never
/// falls back to the screen's sample date/time/gender or the engine's default
/// longitude when the user has not supplied a resolvable birthplace.
class BaziToolExecutor {
  static const String sourceId = 'local-engine:bazi';
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
      return _failure(arguments, '包含未声明的排盘参数，本次未执行。');
    }

    final date = _parseDate(arguments['birth_date']);
    if (date == null) {
      return _failure(arguments, '出生日期缺失或无效；请使用 YYYY-MM-DD。');
    }
    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请使用 24 小时制 HH:mm。');
    }
    final gender = arguments['gender'];
    if (gender != 'male' && gender != 'female') {
      return _failure(arguments, '性别缺失或无效；请选择男或女。');
    }
    final birthplace = arguments['birthplace']?.trim() ?? '';
    if (birthplace.isEmpty) {
      return _failure(arguments, '出生地点缺失；请提供出生城市或区县。');
    }

    final place = await _resolveBirthplace(birthplace);
    if (place == null) {
      return _failure(
        arguments,
        '本地城市目录无法唯一识别「$birthplace」。请补充省/州或所属城市后再排盘；本次未使用默认经纬度。',
      );
    }

    try {
      final settings = SettingsRepository.instance;
      final isMale = gender == 'male';
      final solar = DateTime(date.year, date.month, date.day, time.$1, time.$2);
      final location = Location(place.lng, place.lat);
      final useTrueSolarTime = settings.useTrueSolarTime;
      final distinguishZiShi = settings.distinguishZiShiEnabled;
      final stageMode = settings.fireEarthSame
          ? TwelveStageMode.fireEarthSame
          : TwelveStageMode.waterEarthSame;

      final chart = computeBaZiPaipan(
        solar,
        isMale: isMale,
        useTrueSolarTime: useTrueSolarTime,
        twelveStageMode: stageMode,
        ratHourMode: distinguishZiShi,
        location: location,
      );
      final fortune = computeBaZiFortune(
        solar,
        isMale: isMale,
        location: location,
        ratHourMode: distinguishZiShi,
        useTrueSolarTime: useTrueSolarTime,
      );
      final locationDescription =
          '${place.displayName}（东经：${place.lng.toStringAsFixed(4)}，北纬：${place.lat.toStringAsFixed(4)}）';
      final formatted = formatBaZiChartForAssistant(
        solar: solar,
        isMale: isMale,
        useTrueSolarTime: useTrueSolarTime,
        distinguishZiShi: distinguishZiShi,
        locationDescription: locationDescription,
        result: chart,
        fortune: fortune,
      );

      return AssistantToolResult(
        toolId: 'bazi',
        title: '八字排盘',
        values: {
          '出生地坐标': '东经 ${place.lng.toStringAsFixed(4)}，北纬 ${place.lat.toStringAsFixed(4)}',
          '完整排盘结果': formatted,
        },
        sourceIds: const [sourceId, locationSourceId],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '本结果由 App 本地确定性排盘引擎计算，AI 只负责解释。出生时间按出生地当地钟表时间输入；当前引擎按地点经度执行真太阳时校正，不另做历史时区或夏令时换算。传统命理仅供文化学习参考，不是科学预测，不用于医疗、法律或投资决策。',
      );
    } catch (error) {
      return _failure(arguments, '本地八字引擎执行失败：$error');
    }
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
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static Future<CityLocation?> _resolveBirthplace(String query) async {
    final domestic = await CityLocationService.load(PlaceScope.domestic);
    final domesticMatch = _matchLocation(domestic, query);
    if (domesticMatch != null) return domesticMatch;

    final world = await CityLocationService.load(PlaceScope.world);
    return _matchLocation(world, query);
  }

  static CityLocation? _matchLocation(
    List<CityLocation> locations,
    String query,
  ) {
    final exact = locations.where((place) =>
        place.name == query ||
        place.label == query ||
        place.displayName == query ||
        place.en?.toLowerCase() == query.toLowerCase()).toList();
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null;

    // A short city name such as “上海” may resolve to one city-level record,
    // while an ambiguous district name such as “朝阳” must be clarified.
    final cityLevel = locations
        .where((place) =>
            place.city == null &&
            (place.name.startsWith(query) ||
                (place.en?.toLowerCase() ?? '').startsWith(query.toLowerCase())))
        .toList();
    if (cityLevel.length == 1) return cityLevel.single;
    return null;
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'bazi',
        title: '八字排盘',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数或地点校验未通过；本次未执行排盘。',
      );
}
