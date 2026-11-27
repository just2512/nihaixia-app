import 'package:ziwei_core/ziwei_core.dart' show Gender, Location;

import '../data/settings_repository.dart';
import '../models/assistant_tool_result.dart';
import 'assistant_chart_result_formatter.dart';
import 'city_location_service.dart';
import 'ziwei_engine.dart';

/// Headless adapter for the existing deterministic Ziwei chart engine.
///
/// The assistant must collect explicit Gregorian birth date, local clock time,
/// gender and a uniquely resolvable birthplace. It deliberately does not use
/// the page's sample values or its legacy default longitude.
class ZiweiToolExecutor {
  static const String sourceId = 'local-engine:ziwei';
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
      return _failure(arguments, '出生日期缺失或无效；请使用公历 YYYY-MM-DD。');
    }
    final time = _parseTime(arguments['birth_time']);
    if (time == null) {
      return _failure(arguments, '出生时间缺失或无效；请使用出生地当地钟表时间 HH:mm。');
    }
    final genderValue = arguments['gender'];
    if (genderValue != 'male' && genderValue != 'female') {
      return _failure(arguments, '性别缺失或无效；请明确提供男或女。');
    }
    final birthplace = arguments['birthplace']?.trim() ?? '';
    if (birthplace.isEmpty) {
      return _failure(arguments, '出生地点缺失；请提供出生城市或区县。');
    }

    final place = await _resolveBirthplace(birthplace);
    if (place == null) {
      return _failure(
        arguments,
        '本地城市目录无法唯一识别「$birthplace」。请补充省/州和城市/区县；本次未使用默认经纬度。',
      );
    }

    try {
      final settings = SettingsRepository.instance;
      final solar = DateTime(date.year, date.month, date.day, time.$1, time.$2);
      final gender = genderValue == 'male' ? Gender.male : Gender.female;
      final useTrueSolarTime = settings.useTrueSolarTime;
      final distinguishZiShi = settings.distinguishZiShiEnabled;
      final chart = calculateZiweiChart(
        // Match ZiweiChartScreen exactly: pass the original local clock time.
        // The engine owns late/early Zi handling; do not pre-roll the date.
        solar: solar,
        gender: gender,
        location: Location(place.lng, place.lat),
        useTrueSolarTime: useTrueSolarTime,
        ratHourMode: distinguishZiShi,
      );
      final locationDescription =
          '${place.displayName}（东经：${place.lng.toStringAsFixed(4)}，北纬：${place.lat.toStringAsFixed(4)}）';
      final formatted = formatZiweiChartForAssistant(
        solar: solar,
        useTrueSolarTime: useTrueSolarTime,
        distinguishZiShi: distinguishZiShi,
        locationDescription: locationDescription,
        chart: chart,
      );

      return AssistantToolResult(
        toolId: 'ziwei',
        title: '紫微斗数排盘',
        values: {
          '出生地坐标':
              '东经 ${place.lng.toStringAsFixed(4)}，北纬 ${place.lat.toStringAsFixed(4)}',
          '完整排盘结果': formatted,
        },
        sourceIds: const [sourceId, locationSourceId],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '本结果由 App 本地确定性紫微排盘引擎计算，AI 只负责解释。采用出生地当地钟表时间、App 当前真太阳时与早晚子时设置；不另做历史时区或夏令时换算。紫微斗数属于传统术数文化参考，不是科学预测，不用于医疗、法律或投资决策。',
      );
    } catch (error) {
      return _failure(arguments, '本地紫微排盘引擎执行失败：$error');
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
    final exact = locations
        .where((place) =>
            place.name == query ||
            place.label == query ||
            place.displayName == query ||
            place.en?.toLowerCase() == query.toLowerCase())
        .toList();
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null;

    final normalizedQuery = _normalizeLocationQuery(query);
    final normalized = locations.where((place) {
      final candidates = <String>{
        place.name,
        place.province,
        place.city ?? '',
        '${place.province}${place.name}',
        '${place.name}${place.province}',
        '${place.city ?? ''}${place.name}',
        '${place.province}${place.city ?? ''}${place.name}',
        '${place.city ?? ''}${place.name}${place.province}',
      };
      return candidates
          .where((candidate) => candidate.isNotEmpty)
          .map(_normalizeLocationQuery)
          .contains(normalizedQuery);
    }).toList();
    return normalized.length == 1 ? normalized.single : null;
  }

  static String _normalizeLocationQuery(String value) => value
      .trim()
      .replaceAll(RegExp(r'[\\s,，、·（）()]'), '');

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'ziwei',
        title: '紫微斗数排盘',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数或地点校验未通过；本次未执行紫微排盘。',
      );
}
