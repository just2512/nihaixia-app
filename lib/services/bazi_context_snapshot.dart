import 'package:ziwei_core/ziwei_core.dart' show Location;

import '../engine/bazi_twelve_stages.dart' show TwelveStageMode;
import 'ai_tool_result_snapshot.dart';
import 'assistant_chart_result_formatter.dart';
import 'bazi_service.dart';

/// Structured, content-addressed snapshot for one successfully calculated
/// BaZi chart. This serializes the App engine result; it never infers a chart
/// from rendered text or from an AI response.
class BaziContextSnapshot {
  const BaziContextSnapshot._();

  static const String capabilityId = 'bazi';
  static const String resultSchemaVersion = 'bazi-structured-result-v1';
  static const String sourceId = 'local-engine:bazi';
  static const String locationSourceId = 'local-data:city-locations';

  /// Binds the pinned chart engine packages and every local algorithm/data
  /// asset that participates in this result schema.
  static const String ruleVersion =
      'bazi_core@0.6.7;sxwnl_spa_dart@0.18.5;'
      'bazi-service@724e5dcf4c32c22d62c5f2a1db50e81f8a0f8ffe;'
      'bazi-analysis@809089daf3e85abe405dbcb3b7be217178c5d5cf;'
      'bazi-relations@d9e76a8ce543ec80e57b4279c983b1e84fccc477;'
      'bazi-ten-gods@b1508fd7ce1f9332d7d5cd930cf2354442fa8a82;'
      'bazi-extra@a7c0e5224a9577a0863f891f762298a00b98cddf;'
      'bazi-twelve-stages@2900f418060006a5a94ec617f5dd9e36a51421df;'
      'city-china@5890184a32bc7f830df78c2fae51d7773cb72119;'
      'city-world@951216e7c7bf4ad8a18108813ec2c63a74bb92c9;'
      'formatter@65d2e63a1a06acb0baae3a5eb3367ff0904eef83';

  static const List<String> resultSourceIds = [
    sourceId,
    locationSourceId,
  ];

  /// Serializes the exact successful calculation already displayed by the
  /// screen. A missing birthplace is explicitly represented as ENGINE_DEFAULT
  /// with the same 120E/30N coordinates used by the existing engine.
  static Map<String, Object?> createStructuredSnapshot({
    required DateTime solar,
    required bool isMale,
    required bool useTrueSolarTime,
    required bool distinguishZiShi,
    required bool fireEarthSame,
    required String? birthplaceLabel,
    required double? longitude,
    required double? latitude,
    required BaZiPaipan chart,
    required BaZiFortune fortune,
  }) {
    final selectedCoordinates = longitude != null;
    final hasDirectoryLabel = birthplaceLabel?.trim().isNotEmpty == true;
    final locationMode = !selectedCoordinates
        ? 'ENGINE_DEFAULT'
        : hasDirectoryLabel
            ? 'CITY_DIRECTORY'
            : 'EXPLICIT_COORDINATES';
    final actualLongitude = longitude ?? 120.0;
    final actualLatitude = selectedCoordinates ? (latitude ?? 30.0) : 30.0;
    if (!actualLongitude.isFinite ||
        actualLongitude < -180 ||
        actualLongitude > 180 ||
        !actualLatitude.isFinite ||
        actualLatitude < -90 ||
        actualLatitude > 90) {
      throw ArgumentError('BaZi snapshot coordinates are outside WGS-84 bounds.');
    }
    final resolvedLocationLabel = switch (locationMode) {
      'CITY_DIRECTORY' => birthplaceLabel!.trim(),
      'EXPLICIT_COORDINATES' => 'MISSING（仅提供明确经纬度）',
      _ => '未指定（引擎默认地点）',
    };
    final solarLocal = _formatSolar(solar);
    final location = Location(actualLongitude, actualLatitude);
    final stageMode =
        fireEarthSame ? TwelveStageMode.fireEarthSame : TwelveStageMode.waterEarthSame;

    final pillars = <String, String>{
      'year': chart.bazi.year,
      'month': chart.bazi.month,
      'day': chart.bazi.day,
      'hour': chart.bazi.time,
    };
    final pillarValues = pillars.values.toList(growable: false);
    final analysis = chart.analysis;
    final strengthFactors = analysis.strengthFactors
        .map((value) =>
            value.replaceAll(RegExp(r'\\s*\\([+-]?\\d+(?:\\.\\d+)?\\)'), ''))
        .toList(growable: false);

    final result = <String, Object?>{
      'solarDateTimeLocal': solarLocal,
      'lunarText': chart.lunarText,
      'pillars': pillars,
      'tenGodsByPillar': chart.tenGods,
      'nayinByPillar': pillarValues.map(nayinOfPillar).toList(growable: false),
      'kongWang': chart.kongWang,
      'kongWangByPillar': chart.kongWangPillars,
      'relations': chart.relations,
      'twelveStages': chart.twelveStages,
      'selfStages': chart.selfStages,
      'taiYuan': chart.taiYuan,
      'taiXi': chart.taiXi,
      'hiddenTenGodsByPillar': chart.hiddenTenGods,
      'analysis': <String, Object?>{
        'dayMaster': analysis.dayMaster,
        'pattern': analysis.pattern,
        'patternDescription': analysis.patternDesc,
        'strengthLevel': analysis.strengthLevel,
        'strengthFactors': strengthFactors,
        'fiveElements': [
          for (final item in analysis.fiveElements)
            <String, Object?>{
              'element': item.element,
              'status': item.status,
            },
        ],
        'favorable': analysis.favorable,
        'unfavorable': analysis.unfavorable,
        'suggestion': analysis.suggestion,
        'shensha': [
          for (final item in analysis.shensha)
            <String, Object?>{
              'name': item.name,
              'pillar': item.pillar,
              'position': item.pos,
            },
        ],
      },
      'fortune': <String, Object?>{
        'startAge': fortune.startAge,
        'qiYunTimeLocal': _formatDateTime(fortune.qiYunTime),
        'decades': [
          for (final decade in fortune.decades)
            <String, Object?>{
              'index': decade.index,
              'ganZhi': decade.ganZhi,
              'startAge': decade.startAge,
              'endAge': decade.endAge,
              'flowYears': [
                for (final year in decade.years)
                  <String, Object?>{
                    'year': year.year,
                    'ganZhi': year.ganZhi,
                  },
              ],
            },
        ],
      },
    };

    final locationDescription = locationMode == 'CITY_DIRECTORY'
        ? '$resolvedLocationLabel（东经：${actualLongitude.toStringAsFixed(4)}，'
            '北纬：${actualLatitude.toStringAsFixed(4)}）'
        : locationMode == 'EXPLICIT_COORDINATES'
            ? '地点名称 MISSING；明确坐标：东经/西经 ${actualLongitude.toStringAsFixed(4)}，'
                '北纬/南纬 ${actualLatitude.toStringAsFixed(4)}'
            : '未指定；引擎默认地点为东经120°、北纬30°';
    final summary = formatBaZiChartForAssistant(
      solar: solar,
      isMale: isMale,
      useTrueSolarTime: useTrueSolarTime,
      distinguishZiShi: distinguishZiShi,
      locationDescription: locationDescription,
      result: chart,
      fortune: fortune,
    );

    final payload = <String, Object?>{
      'capabilityId': capabilityId,
      'resultSchemaVersion': resultSchemaVersion,
      'executionStatus': 'SUCCESS',
      'ruleVersion': ruleVersion,
      'sourceIds': [
        sourceId,
        if (locationMode == 'CITY_DIRECTORY') locationSourceId,
      ],
      'input': <String, Object?>{
        'solarDateTimeLocal': solarLocal,
        'birthDate': solarLocal.substring(0, 10),
        'birthTime': solarLocal.substring(11),
        'gender': isMale ? 'male' : 'female',
        'genderLabel': isMale ? '男' : '女',
        'birthplace': <String, Object?>{
          'mode': locationMode,
          'label': resolvedLocationLabel,
          'longitude': actualLongitude,
          'latitude': actualLatitude,
          'coordinateDatum': 'WGS-84',
          'sourceId': locationMode == 'CITY_DIRECTORY'
              ? locationSourceId
              : locationMode == 'EXPLICIT_COORDINATES'
                  ? 'USER_INPUT'
                  : 'ENGINE_DEFAULT',
        },
        'settings': <String, Object?>{
          'useTrueSolarTime': useTrueSolarTime,
          'distinguishZiShi': distinguishZiShi,
          'twelveStageMode':
              stageMode == TwelveStageMode.fireEarthSame ? 'fireEarthSame' : 'waterEarthSame',
        },
      },
      'result': result,
      'units': <String, Object?>{
        'solarDateTimeLocal': '出生地当地钟表时间；不自动换算历史时区或夏令时',
        'longitude': 'degrees east-positive, WGS-84',
        'latitude': 'degrees north-positive, WGS-84',
        'fortune.startAge': '虚岁',
        'fortune.decades.startAge': '虚岁',
        'fortune.decades.endAge': '虚岁',
        'fortune.flowYears.year': '公历年',
      },
      'missingFields': const <String>[],
      'displaySummary': summary,
    };
    return _freeze({
      ...payload,
      'snapshotId': AiToolResultSnapshot.createStructuredId(snapshot: payload),
    }) as Map<String, Object?>;
  }

  /// Rebuilds the deterministic result from the immutable input stored inside
  /// a snapshot. Used by the resolver to reject a modified payload or stale
  /// engine/configuration version before any of it reaches the local model.
  static Map<String, Object?> recomputeFromInput(
    Map<String, Object?> input,
  ) {
    final solarValue = input['solarDateTimeLocal'];
    final gender = input['gender'];
    final birthplace = input['birthplace'];
    final settings = input['settings'];
    if (solarValue is! String ||
        gender is! String ||
        birthplace is! Map ||
        settings is! Map) {
      throw ArgumentError('BaZi snapshot input is incomplete.');
    }
    final solar = _parseSolar(solarValue);
    if (solar == null || (gender != 'male' && gender != 'female')) {
      throw ArgumentError('BaZi snapshot date/time or gender is invalid.');
    }
    final mode = birthplace['mode'];
    final label = birthplace['label'];
    final longitude = birthplace['longitude'];
    final latitude = birthplace['latitude'];
    if (mode is! String ||
        label is! String ||
        longitude is! num ||
        latitude is! num ||
        (mode != 'CITY_DIRECTORY' && mode != 'ENGINE_DEFAULT')) {
      throw ArgumentError('BaZi snapshot birthplace is invalid.');
    }
    final cityDirectoryLocation = mode == 'CITY_DIRECTORY';
    final explicitCoordinates = mode == 'EXPLICIT_COORDINATES';
    final defaultLocation = mode == 'ENGINE_DEFAULT';
    if (cityDirectoryLocation &&
        (label.trim().isEmpty ||
            birthplace['sourceId'] != locationSourceId)) {
      throw ArgumentError('A city-directory birthplace requires its local city source.');
    }
    if (explicitCoordinates &&
        (label != 'MISSING' && !label.startsWith('MISSING') ||
            birthplace['sourceId'] != 'USER_INPUT')) {
      throw ArgumentError('Explicit coordinates must not claim a city-directory record.');
    }
    if (defaultLocation && birthplace['sourceId'] != 'ENGINE_DEFAULT') {
      throw ArgumentError('An engine-default birthplace cannot claim a city source.');
    }
    final useTrueSolarTime = settings['useTrueSolarTime'];
    final distinguishZiShi = settings['distinguishZiShi'];
    final stageMode = settings['twelveStageMode'];
    if (useTrueSolarTime is! bool ||
        distinguishZiShi is! bool ||
        (stageMode != 'fireEarthSame' && stageMode != 'waterEarthSame')) {
      throw ArgumentError('BaZi snapshot calculation settings are invalid.');
    }

    final isMale = gender == 'male';
    final location = Location(longitude.toDouble(), latitude.toDouble());
    final fireEarthSame = stageMode == 'fireEarthSame';
    final chart = computeBaZiPaipan(
      solar,
      isMale: isMale,
      useTrueSolarTime: useTrueSolarTime,
      twelveStageMode: fireEarthSame
          ? TwelveStageMode.fireEarthSame
          : TwelveStageMode.waterEarthSame,
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
    return createStructuredSnapshot(
      solar: solar,
      isMale: isMale,
      useTrueSolarTime: useTrueSolarTime,
      distinguishZiShi: distinguishZiShi,
      fireEarthSame: fireEarthSame,
      birthplaceLabel: cityDirectoryLocation ? label : null,
      longitude: defaultLocation ? null : longitude.toDouble(),
      latitude: defaultLocation ? null : latitude.toDouble(),
      chart: chart,
      fortune: fortune,
    );
  }

  static Object? _freeze(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          entry.key.toString(): _freeze(entry.value),
      });
    }
    if (value is Iterable) {
      return List<Object?>.unmodifiable(value.map(_freeze));
    }
    return value;
  }

  static String _formatSolar(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}T'
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static String _formatDateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}T'
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static DateTime? _parseSolar(String value) {
    final match =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
      return null;
    }
    final valueDate = DateTime(year, month, day, hour, minute);
    if (valueDate.year != year ||
        valueDate.month != month ||
        valueDate.day != day ||
        valueDate.hour != hour ||
        valueDate.minute != minute) {
      return null;
    }
    return valueDate;
  }
}
