import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';

void main() {
  test('same input, rules and result produce the same snapshot id', () {
    const input = {
      'solar': '2000-08-16T10:00:00.000',
      'gender': '男',
      'longitude': 121.47,
      'latitude': 31.23,
      'useTrueSolarTime': true,
      'distinguishZiShi': false,
    };
    final first = AiToolResultSnapshot.createId(
      input: input,
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：紫微；十二宫星曜……',
    );
    final repeated = AiToolResultSnapshot.createId(
      input: {
        'distinguishZiShi': false,
        'latitude': 31.23,
        'longitude': 121.47,
        'gender': '男',
        'solar': '2000-08-16T10:00:00.000',
        'useTrueSolarTime': true,
      },
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：紫微；十二宫星曜……',
    );
    expect(first, hasLength(64));
    expect(repeated, first);
  });

  test('coordinates, engine rules and formatted result are snapshot inputs', () {
    const input = {
      'solar': '2000-08-16T10:00:00.000',
      'gender': '男',
      'longitude': 121.47,
      'latitude': 31.23,
      'useTrueSolarTime': true,
      'distinguishZiShi': false,
    };
    final original = AiToolResultSnapshot.createId(
      input: input,
      ruleVersion: 'ziwei_core@0.13.0',
      resultPayload: '命宫：紫微',
    );
    final changedLongitude = AiToolResultSnapshot.createId(
      input: {...input, 'longitude': 120.0},
      ruleVersion: 'ziwei_core@0.13.0',
      resultPayload: '命宫：紫微',
    );
    final changedLatitude = AiToolResultSnapshot.createId(
      input: {...input, 'latitude': 30.0},
      ruleVersion: 'ziwei_core@0.13.0',
      resultPayload: '命宫：紫微',
    );
    final changedRule = AiToolResultSnapshot.createId(
      input: input,
      ruleVersion: 'ziwei_core@0.13.1',
      resultPayload: '命宫：紫微',
    );
    final changedResult = AiToolResultSnapshot.createId(
      input: input,
      ruleVersion: 'ziwei_core@0.13.0',
      resultPayload: '命宫：天府',
    );

    expect(changedLongitude, isNot(original));
    expect(changedLatitude, isNot(original));
    expect(changedRule, isNot(original));
    expect(changedResult, isNot(original));
  });

  test('structured result snapshots canonicalize nested map key order', () {
    final first = AiToolResultSnapshot.createId(
      input: const {
        'solar': '2000-08-16T10:00:00.000',
        'options': {'trueSolarTime': true, 'location': {'lat': 31.23, 'lng': 121.47}},
      },
      ruleVersion: 'ziwei_structured_v1',
      resultPayload: const {
        'palaces': [
          {'index': 0, 'stars': [{'key': 'ziwei', 'brightness': '庙'}]},
        ],
        'lunar': {'month': 7, 'leap': false},
      },
    );
    final reordered = AiToolResultSnapshot.createId(
      input: const {
        'options': {'location': {'lng': 121.47, 'lat': 31.23}, 'trueSolarTime': true},
        'solar': '2000-08-16T10:00:00.000',
      },
      ruleVersion: 'ziwei_structured_v1',
      resultPayload: const {
        'lunar': {'leap': false, 'month': 7},
        'palaces': [
          {'stars': [{'brightness': '庙', 'key': 'ziwei'}], 'index': 0},
        ],
      },
    );
    final changedField = AiToolResultSnapshot.createId(
      input: const {
        'options': {'location': {'lng': 121.47, 'lat': 31.23}, 'trueSolarTime': true},
        'solar': '2000-08-16T10:00:00.000',
      },
      ruleVersion: 'ziwei_structured_v1',
      resultPayload: const {
        'lunar': {'leap': false, 'month': 7},
        'palaces': [
          {'stars': [{'brightness': '旺', 'key': 'ziwei'}], 'index': 0},
        ],
      },
    );

    expect(reordered, first);
    expect(changedField, isNot(first));
  });

  test('legacy string result payload remains content-addressed', () {
    final id = AiToolResultSnapshot.createId(
      input: const {'solar': '2000-08-16T10:00:00.000'},
      ruleVersion: 'ziwei_core@0.13.0',
      resultPayload: '命宫：紫微',
    );

    expect(id, hasLength(64));
  });
}
