import 'package:flutter_test/flutter_test.dart';
import 'package:ziwei_core/ziwei_core.dart' show Location;

import 'package:nihaisha_app/engine/bazi_twelve_stages.dart'
    show TwelveStageMode;
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/bazi_context_snapshot.dart';
import 'package:nihaisha_app/services/bazi_service.dart';

void main() {
  Map<String, Object?> buildSnapshot({
    DateTime? solar,
    bool isMale = true,
    bool useTrueSolarTime = true,
    bool distinguishZiShi = false,
    bool fireEarthSame = true,
    String? birthplaceLabel = '上海市（上海市）',
    double? longitude = 121.4737,
    double? latitude = 31.2304,
  }) {
    final date = solar ?? DateTime(2000, 8, 16, 10, 30);
    final location = Location(longitude ?? 120, latitude ?? 30);
    final chart = computeBaZiPaipan(
      date,
      isMale: isMale,
      useTrueSolarTime: useTrueSolarTime,
      twelveStageMode: fireEarthSame
          ? TwelveStageMode.fireEarthSame
          : TwelveStageMode.waterEarthSame,
      ratHourMode: distinguishZiShi,
      location: location,
    );
    final fortune = computeBaZiFortune(
      date,
      isMale: isMale,
      location: location,
      ratHourMode: distinguishZiShi,
      useTrueSolarTime: useTrueSolarTime,
    );
    return BaziContextSnapshot.createStructuredSnapshot(
      solar: date,
      isMale: isMale,
      useTrueSolarTime: useTrueSolarTime,
      distinguishZiShi: distinguishZiShi,
      fireEarthSame: fireEarthSame,
      birthplaceLabel: birthplaceLabel,
      longitude: longitude,
      latitude: latitude,
      chart: chart,
      fortune: fortune,
    );
  }

  test('Bazi structured snapshot binds exact inputs, all result layers and real sources', () {
    final snapshot = buildSnapshot();
    final input = snapshot['input']! as Map<String, Object?>;
    final birthplace = input['birthplace']! as Map<String, Object?>;
    final settings = input['settings']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final pillars = result['pillars']! as Map<String, String>;
    final analysis = result['analysis']! as Map<String, Object?>;
    final fortune = result['fortune']! as Map<String, Object?>;

    expect(snapshot['capabilityId'], 'bazi');
    expect(snapshot['resultSchemaVersion'], BaziContextSnapshot.resultSchemaVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(snapshot['ruleVersion'], BaziContextSnapshot.ruleVersion);
    expect(snapshot['sourceIds'], [
      BaziContextSnapshot.sourceId,
      BaziContextSnapshot.locationSourceId,
    ]);
    expect(input['solarDateTimeLocal'], '2000-08-16T10:30');
    expect(input['birthDate'], '2000-08-16');
    expect(input['birthTime'], '10:30');
    expect(input['gender'], 'male');
    expect(birthplace['mode'], 'CITY_DIRECTORY');
    expect(birthplace['label'], '上海市（上海市）');
    expect(birthplace['longitude'], 121.4737);
    expect(birthplace['latitude'], 31.2304);
    expect(birthplace['sourceId'], BaziContextSnapshot.locationSourceId);
    expect(settings['useTrueSolarTime'], isTrue);
    expect(settings['distinguishZiShi'], isFalse);
    expect(settings['twelveStageMode'], 'fireEarthSame');

    expect(pillars.keys, containsAll(['year', 'month', 'day', 'hour']));
    expect((result['tenGodsByPillar']! as List).length, 4);
    expect((result['nayinByPillar']! as List).length, 4);
    expect((result['hiddenTenGodsByPillar']! as List).length, 4);
    expect(result['lunarText'], isA<String>());
    expect(result['twelveStages'], isA<List<String>>());
    expect(result['selfStages'], isA<List<String>>());
    expect(analysis['dayMaster'], isA<String>());
    expect(analysis['strengthLevel'], isA<String>());
    expect(analysis['fiveElements'], isA<List<Map<String, Object?>>>());
    expect(analysis.containsKey('strengthScore'), isFalse);
    expect(
      (analysis['fiveElements']! as List).every(
        (item) => !(item as Map).containsKey('score'),
      ),
      isTrue,
      reason: '不得将内部强弱评分与五行分值包装成未经解释的权威指标',
    );
    expect(fortune['startAge'], isA<double>());
    expect(fortune['qiYunTimeLocal'], isA<String>());
    expect((fortune['decades']! as List).length, 8);
    expect(snapshot['units'], isA<Map<String, Object?>>());
    expect(snapshot['missingFields'], isEmpty);
    expect(snapshot['displaySummary'], contains('【八字排盘完整结果】'));
    expect(snapshot['snapshotId'], hasLength(64));
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );
  });

  test('same engine inputs reproduce the same Bazi snapshot and changed inputs do not', () {
    final first = buildSnapshot();
    final repeated = buildSnapshot();
    final changedDate = buildSnapshot(solar: DateTime(2000, 8, 17, 10, 30));
    final changedLocation = buildSnapshot(longitude: 120, latitude: 30);
    final changedMode = buildSnapshot(fireEarthSame: false);
    final changedTimeRule = buildSnapshot(distinguishZiShi: true);

    expect(repeated['snapshotId'], first['snapshotId']);
    expect(changedDate['snapshotId'], isNot(first['snapshotId']));
    expect(changedLocation['snapshotId'], isNot(first['snapshotId']));
    expect(changedMode['snapshotId'], isNot(first['snapshotId']));
    expect(changedTimeRule['snapshotId'], isNot(first['snapshotId']));

    final rebuilt = BaziContextSnapshot.recomputeFromInput(
      first['input']! as Map<String, Object?>,
    );
    expect(rebuilt['snapshotId'], first['snapshotId']);
  });

  test('unspecified birthplace is explicit and never relabelled as the user birthplace', () {
    final snapshot = buildSnapshot(
      birthplaceLabel: null,
      longitude: null,
      latitude: null,
    );
    final input = snapshot['input']! as Map<String, Object?>;
    final birthplace = input['birthplace']! as Map<String, Object?>;

    expect(snapshot['sourceIds'], [BaziContextSnapshot.sourceId]);
    expect(birthplace['mode'], 'ENGINE_DEFAULT');
    expect(birthplace['label'], '未指定（引擎默认地点）');
    expect(birthplace['longitude'], 120.0);
    expect(birthplace['latitude'], 30.0);
    expect(birthplace['sourceId'], 'ENGINE_DEFAULT');

    final rebuilt = BaziContextSnapshot.recomputeFromInput(input);
    expect(rebuilt['snapshotId'], snapshot['snapshotId']);
  });

  test('recomputation rejects malformed or ambiguous birthplace provenance', () {
    final snapshot = buildSnapshot();
    final input = Map<String, Object?>.from(
      snapshot['input']! as Map<String, Object?>,
    );
    final wrongPlace = Map<String, Object?>.from(
      input['birthplace']! as Map<String, Object?>,
    )..['sourceId'] = 'unverified:city';
    input['birthplace'] = wrongPlace;

    expect(
      () => BaziContextSnapshot.recomputeFromInput(input),
      throwsArgumentError,
    );

    final invalidTime = Map<String, Object?>.from(
      snapshot['input']! as Map<String, Object?>,
    )..['solarDateTimeLocal'] = '2000-02-30T25:99';
    expect(
      () => BaziContextSnapshot.recomputeFromInput(invalidTime),
      throwsArgumentError,
    );
  });
}
