import 'package:ziwei_core/ziwei_core.dart' show Location;

import '../engine/bazi_twelve_stages.dart' show TwelveStageMode;
import '../services/ai_tool_result_snapshot.dart';
import '../services/assistant_chart_result_formatter.dart';
import '../services/bazi_service.dart';

/// Immutable, source-bound snapshot of the exact Bazi result already rendered
/// by BaZiPaipanScreen. The resolver rebuilds this payload from its recorded
/// birth inputs, effective settings and location provenance before prompting.
class BaziContextSnapshot {
  BaziContextSnapshot._();

  static const moduleId = 'bazi';
  static const sourceId = 'local-engine:bazi';
  static const citySourceId = 'local-data:city-locations';
  static const coordinateInputSourceId = 'local-input:bazi-location-coordinates';
  static const defaultLocationSourceId = 'local-config:bazi-default-location';
  static const resultSchemaVersion = 'bazi-structured-result-v1';

  // Each source digest is the Git blob SHA for the exact implementation/data
  // used by this calculation. External package versions are pinned separately.
  static const ruleVersion = 'bazi-v1;'
      'service@724e5dcf4c32c22d62c5f2a1db50e81f8a0f8ffe;'
      'analysis@809089daf3e85abe405dbcb3b7be217178c5d5cf;'
      'relations@d9e76a8ce543ec80e57b4279c983b1e84fccc477;'
      'ten-gods@b1508fd7ce1f9332d7d5cd930cf2354442fa8a82;'
      'twelve-stages@2900f418060006a5a94ec617f5dd9e36a51421df;'
      'extra@a7c0e5224a9577a0863f891f762298a00b98cddf;'
      'formatter@65d2e63a1a06acb0baae3a5eb3367ff0904eef83;'
      'china-cities@5890184a32bc7f830df78c2fae51d7773cb72119;'
      'world-cities@951216e7c7bf4ad8a18108813ec2c63a74bb92c9;'
      'bazi_core@0.6.7;ziwei_core@0.13.0;sxwnl_spa_dart@0.18.5';

  static const disclaimer =
      '由 App 本地八字引擎确定性计算；传统子平命理文化学习参考，不是科学预测。'
      '不得据此形成医疗诊断、治疗建议、法律判断、投资建议或其他重大决定。';

  /// Builds a snapshot directly from the exact result currently visible on
  /// BaZiPaipanScreen. No second calculation or default-value substitution is
  /// performed while creating the initial context.
  static Map<String, Object?> createFromCurrentResult({
    required Map<String, String> arguments,
    required BaZiPaipan result,
    required BaZiFortune? fortune,
    required String locationMode,
    required String? locationLabel,
    required double longitude,
    required double latitude,
    required bool useTrueSolarTime,
    required bool distinguishZiShi,
    required TwelveStageMode twelveStageMode,
  }) {
    final normalizedArguments = _validateArguments(arguments);
    final location = _normalizeLocation(
      mode: locationMode,
      label: locationLabel,
      longitude: longitude,
      latitude: latitude,
    );
    final settings = <String, Object?>{
      'useTrueSolarTime': useTrueSolarTime,
      'distinguishZiShi': distinguishZiShi,
      'twelveStageMode': twelveStageMode.name,
    };
    return _buildSnapshot(
      arguments: normalizedArguments,
      location: location,
      settings: settings,
      result: result,
      fortune: fortune,
    );
  }

  /// Rebuilds a snapshot using only its recorded, validated calculation input.
  /// This is used by the resolver; current UI fields or saved defaults are not
  /// read implicitly.
  static Map<String, Object?> rebuildFromInput({
    required Map<String, Object?> input,
  }) {
    final argumentsValue = input['arguments'];
    final locationValue = input['location'];
    final settingsValue = input['settings'];
    if (argumentsValue is! Map ||
        locationValue is! Map ||
        settingsValue is! Map) {
      throw ArgumentError('The Bazi snapshot input is incomplete.');
    }

    final arguments = <String, String>{};
    for (final entry in argumentsValue.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw ArgumentError('Bazi input arguments must be string pairs.');
      }
      arguments[entry.key as String] = entry.value as String;
    }
    final normalizedArguments = _validateArguments(arguments);
    final location = _validateLocationMap(locationValue);
    final settings = _validateSettings(settingsValue);
    final mode = location['mode'];
    final expectedBirthplace = switch (mode) {
      'city-directory' => location['label'],
      'provided-coordinates' => '用户提供坐标',
      'engine-default' => 'MISSING',
      _ => null,
    };
    if (normalizedArguments['birthplace'] != expectedBirthplace) {
      throw ArgumentError(
        'Bazi birthplace argument does not match the recorded location provenance.',
      );
    }

    final date = _parseDate(normalizedArguments['birth_date']!);
    final time = _parseTime(normalizedArguments['birth_time']!);
    final isMale = normalizedArguments['gender'] == 'male';
    final solar = DateTime(date.year, date.month, date.day, time.$1, time.$2);
    final engineLocation = location['mode'] == 'engine-default'
        ? null
        : Location(
            location['longitude']! as double,
            location['latitude']! as double,
          );
    final stageMode = settings['twelveStageMode'] == 'fireEarthSame'
        ? TwelveStageMode.fireEarthSame
        : TwelveStageMode.waterEarthSame;

    final result = computeBaZiPaipan(
      solar,
      isMale: isMale,
      useTrueSolarTime: settings['useTrueSolarTime']! as bool,
      twelveStageMode: stageMode,
      ratHourMode: settings['distinguishZiShi']! as bool,
      location: engineLocation,
    );
    final fortune = computeBaZiFortune(
      solar,
      isMale: isMale,
      location: engineLocation,
      ratHourMode: settings['distinguishZiShi']! as bool,
      useTrueSolarTime: settings['useTrueSolarTime']! as bool,
    );
    return _buildSnapshot(
      arguments: normalizedArguments,
      location: location,
      settings: settings,
      result: result,
      fortune: fortune,
    );
  }

  static Map<String, Object?> _buildSnapshot({
    required Map<String, String> arguments,
    required Map<String, Object?> location,
    required Map<String, Object?> settings,
    required BaZiPaipan result,
    required BaZiFortune? fortune,
  }) {
    final solar = _parseDate(arguments['birth_date']!);
    final time = _parseTime(arguments['birth_time']!);
    final birthDateTime = DateTime(
      solar.year,
      solar.month,
      solar.day,
      time.$1,
      time.$2,
    );
    final pillars = <String, String>{
      'year': result.bazi.year,
      'month': result.bazi.month,
      'day': result.bazi.day,
      'hour': result.bazi.time,
    };
    final pillarNames = const ['年柱', '月柱', '日柱', '时柱'];
    final analysis = result.analysis;
    final locationDescription = _locationDescription(location);
    final formatted = formatBaZiChartForAssistant(
      solar: birthDateTime,
      isMale: arguments['gender'] == 'male',
      useTrueSolarTime: settings['useTrueSolarTime']! as bool,
      distinguishZiShi: settings['distinguishZiShi']! as bool,
      locationDescription: locationDescription,
      result: result,
      fortune: fortune,
    );

    final resultData = <String, Object?>{
      'birthDateTime': birthDateTime.toIso8601String(),
      'birthplace': Map<String, Object?>.unmodifiable(location),
      'birthLunar': result.lunarText,
      'pillars': Map<String, Object?>.unmodifiable({
        'year': pillars['year'],
        'month': pillars['month'],
        'day': pillars['day'],
        'hour': pillars['hour'],
        'gans': List<String>.unmodifiable(result.gans),
        'zhis': List<String>.unmodifiable(result.zhis),
        'nayin': Map<String, String>.unmodifiable({
          'year': nayinOfPillar(result.bazi.year),
          'month': nayinOfPillar(result.bazi.month),
          'day': nayinOfPillar(result.bazi.day),
          'hour': nayinOfPillar(result.bazi.time),
        }),
      }),
      'tenGods': List<String>.unmodifiable(result.tenGods),
      'kongWang': List<String>.unmodifiable(result.kongWang),
      'kongWangPillars': List<String>.unmodifiable(result.kongWangPillars),
      'relations': List<String>.unmodifiable(result.relations),
      'twelveStages': List<String>.unmodifiable(result.twelveStages),
      'selfStages': List<String>.unmodifiable(result.selfStages),
      'taiYuan': result.taiYuan,
      'taiXi': result.taiXi,
      'hiddenTenGods': [
        for (var i = 0; i < result.hiddenTenGods.length; i++)
          Map<String, Object?>.unmodifiable({
            'pillar': pillarNames[i],
            'items': List<String>.unmodifiable(result.hiddenTenGods[i]),
          }),
      ],
      'analysis': Map<String, Object?>.unmodifiable({
        'dayMaster': analysis.dayMaster,
        'pattern': analysis.pattern,
        'patternDescription': analysis.patternDesc,
        'strengthLevel': analysis.strengthLevel,
        'strengthScore': analysis.strengthScore,
        'strengthFactors': List<String>.unmodifiable(analysis.strengthFactors),
        'fiveElements': [
          for (final item in analysis.fiveElements)
            Map<String, Object?>.unmodifiable({
              'element': item.element,
              'score': item.score,
              'status': item.status,
            }),
        ],
        'favorable': List<String>.unmodifiable(analysis.favorable),
        'unfavorable': List<String>.unmodifiable(analysis.unfavorable),
        'suggestion': analysis.suggestion,
        'shensha': [
          for (final item in analysis.shensha)
            Map<String, Object?>.unmodifiable({
              'name': item.name,
              'pillar': item.pillar,
              'position': item.pos,
            }),
        ],
      }),
      'fortune': fortune == null
          ? null
          : Map<String, Object?>.unmodifiable({
              'startAge': fortune.startAge,
              'qiYunTime': fortune.qiYunTime.toIso8601String(),
              'decades': [
                for (final decade in fortune.decades)
                  Map<String, Object?>.unmodifiable({
                    'index': decade.index,
                    'ganZhi': decade.ganZhi,
                    'startAge': decade.startAge,
                    'endAge': decade.endAge,
                    'years': [
                      for (final year in decade.years)
                        Map<String, Object?>.unmodifiable({
                          'year': year.year,
                          'ganZhi': year.ganZhi,
                        }),
                    ],
                  }),
              ],
            }),
    };

    final sourceIds = <String>[
      sourceId,
      'package:bazi_core@0.6.7',
      'package:sxwnl_spa_dart@0.18.5',
      'package:ziwei_core@0.13.0',
      switch (location['mode']) {
        'city-directory' => citySourceId,
        'provided-coordinates' => coordinateInputSourceId,
        'engine-default' => defaultLocationSourceId,
        _ => throw ArgumentError('Unknown Bazi location provenance.'),
      },
    ];
    final base = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': List<String>.unmodifiable(sourceIds),
      'ruleVersion': ruleVersion,
      'input': Map<String, Object?>.unmodifiable({
        'arguments': Map<String, String>.unmodifiable(arguments),
        'location': Map<String, Object?>.unmodifiable(location),
        'settings': Map<String, Object?>.unmodifiable(settings),
      }),
      'result': Map<String, Object?>.unmodifiable(resultData),
      'units': const <String, String>{
        'birthDateTime': 'Gregorian local clock time at birthplace; no historical time-zone/DST conversion',
        'longitude': 'WGS-84 degrees east; east positive',
        'latitude': 'WGS-84 degrees north; north positive',
        'strengthScore': 'Internal deterministic engine score; not a probability or statistical confidence',
        'fiveElements.score': 'Internal deterministic element score; not a population frequency or probability',
        'fortune.startAge': 'Traditional virtual-age convention used by the local engine',
        'fortune.decadeAges': 'Traditional virtual ages returned by the local engine',
      },
      'missingFields': fortune == null ? const ['fortune'] : const <String>[],
      'displaySummary': Map<String, Object?>.unmodifiable({
        'title': '八字排盘',
        'values': Map<String, String>.unmodifiable({
          '出生地坐标':
              '东经 ${(location['longitude']! as double).toStringAsFixed(4)}，北纬 ${(location['latitude']! as double).toStringAsFixed(4)}',
          '完整排盘结果': formatted,
        }),
        'disclaimer': disclaimer,
      }),
    };
    final snapshotId = AiToolResultSnapshot.createStructuredId(snapshot: base);
    return _freezeMap({
      ...base,
      'snapshotId': snapshotId,
    });
  }

  static Map<String, String> _validateArguments(Map<String, String> input) {
    const required = {'birth_date', 'birth_time', 'gender', 'birthplace'};
    if (input.keys.toSet().difference(required).isNotEmpty ||
        !input.keys.toSet().containsAll(required)) {
      throw ArgumentError('Bazi context requires the exact declared birth arguments.');
    }
    _parseDate(input['birth_date']!);
    _parseTime(input['birth_time']!);
    if (input['gender'] != 'male' && input['gender'] != 'female') {
      throw ArgumentError('Bazi gender must be male or female.');
    }
    if (input['birthplace']!.trim().isEmpty) {
      throw ArgumentError('Bazi birthplace label must be explicit.');
    }
    return Map<String, String>.unmodifiable(input);
  }

  static Map<String, Object?> _normalizeLocation({
    required String mode,
    required String? label,
    required double longitude,
    required double latitude,
  }) {
    if (!longitude.isFinite ||
        !latitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        latitude < -90 ||
        latitude > 90) {
      throw ArgumentError('Bazi coordinates are outside WGS-84 bounds.');
    }
    if (!const {
      'city-directory',
      'provided-coordinates',
      'engine-default',
    }.contains(mode)) {
      throw ArgumentError('Bazi location provenance is not recognized.');
    }
    if (mode == 'engine-default' &&
        (longitude != 120 || latitude != 30)) {
      throw ArgumentError('The Bazi engine default location is fixed at 120E, 30N.');
    }
    if (mode == 'city-directory' && (label == null || label.trim().isEmpty)) {
      throw ArgumentError('A city-directory location requires its exact label.');
    }
    final normalizedLabel = label?.trim();
    return Map<String, Object?>.unmodifiable({
      'mode': mode,
      'label': normalizedLabel == null || normalizedLabel.isEmpty
          ? 'MISSING'
          : normalizedLabel,
      'longitude': longitude,
      'latitude': latitude,
      'coordinateSystem': 'WGS-84',
    });
  }

  static Map<String, Object?> _validateLocationMap(Map raw) {
    final mode = raw['mode'];
    final label = raw['label'];
    final longitude = raw['longitude'];
    final latitude = raw['latitude'];
    if (mode is! String ||
        label is! String ||
        longitude is! num ||
        latitude is! num ||
        raw['coordinateSystem'] != 'WGS-84') {
      throw ArgumentError('Bazi location metadata is malformed.');
    }
    return _normalizeLocation(
      mode: mode,
      label: label == 'MISSING' ? null : label,
      longitude: longitude.toDouble(),
      latitude: latitude.toDouble(),
    );
  }

  static Map<String, Object?> _validateSettings(Map raw) {
    final useTrueSolarTime = raw['useTrueSolarTime'];
    final distinguishZiShi = raw['distinguishZiShi'];
    final twelveStageMode = raw['twelveStageMode'];
    if (useTrueSolarTime is! bool ||
        distinguishZiShi is! bool ||
        twelveStageMode is! String ||
        !const {'fireEarthSame', 'waterEarthSame'}.contains(twelveStageMode)) {
      throw ArgumentError('Bazi calculation settings are malformed.');
    }
    return Map<String, Object?>.unmodifiable({
      'useTrueSolarTime': useTrueSolarTime,
      'distinguishZiShi': distinguishZiShi,
      'twelveStageMode': twelveStageMode,
    });
  }

  static DateTime _parseDate(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) throw ArgumentError('Bazi date must use YYYY-MM-DD.');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      throw ArgumentError('Bazi birth date is not a valid Gregorian date.');
    }
    return value;
  }

  static (int, int) _parseTime(String raw) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw);
    if (match == null) throw ArgumentError('Bazi time must use HH:mm.');
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      throw ArgumentError('Bazi local clock time is outside the 24-hour range.');
    }
    return (hour, minute);
  }

  static String _locationDescription(Map<String, Object?> location) {
    final mode = location['mode'];
    final label = location['label'] as String;
    if (mode == 'engine-default') {
      return '未指定（使用引擎默认地点：东经120°、北纬30°）';
    }
    if (mode == 'city-directory') {
      return '$label（东经：${(location['longitude']! as double).toStringAsFixed(4)}，北纬：${(location['latitude']! as double).toStringAsFixed(4)}）';
    }
    return '用户提供坐标（东经：${(location['longitude']! as double).toStringAsFixed(4)}，北纬：${(location['latitude']! as double).toStringAsFixed(4)}）';
  }
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key: _freezeValue(entry.value),
    });

Object? _freezeValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezeValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}
