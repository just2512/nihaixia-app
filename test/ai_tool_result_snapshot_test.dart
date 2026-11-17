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
}
