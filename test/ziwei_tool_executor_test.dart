import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/ziwei_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validArguments = {
    'birth_date': '1990-01-02',
    'birth_time': '08:30',
    'gender': 'male',
    'birthplace': '上海市',
  };

  test('紫微 Headless 执行复用本地引擎和城市坐标并返回完整排盘来源', () async {
    final result = await ZiweiToolExecutor.execute(validArguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'ziwei');
    expect(result.validateFor('ziwei'), isEmpty);
    expect(result.validateArgumentsMatch(validArguments), isEmpty);
    expect(result.sourceIds, [
      ZiweiToolExecutor.sourceId,
      ZiweiToolExecutor.locationSourceId,
    ]);
    expect(result.values['出生地坐标'], contains('东经'));
    expect(result.values['完整排盘结果'], contains('1990-01-02 08:30'));
    expect(result.values['完整排盘结果'], contains('十二宫星曜'));
    expect(result.values['完整排盘结果'], contains('本地确定性紫微排盘引擎'));
    expect(result.disclaimer, contains('不用于医疗、法律或投资决策'));
  });

  test('不接受无效公历日期、时刻或缺失性别，不使用页面默认值', () async {
    final invalidDate = await ZiweiToolExecutor.execute({
      ...validArguments,
      'birth_date': '1990-02-30',
    });
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('出生日期'));

    final invalidTime = await ZiweiToolExecutor.execute({
      ...validArguments,
      'birth_time': '25:90',
    });
    expect(invalidTime.status, AssistantToolExecutionStatus.failed);
    expect(invalidTime.values['未执行原因'], contains('出生时间'));

    final missingGender = await ZiweiToolExecutor.execute({
      'birth_date': validArguments['birth_date']!,
      'birth_time': validArguments['birth_time']!,
      'birthplace': validArguments['birthplace']!,
    });
    expect(missingGender.status, AssistantToolExecutionStatus.failed);
    expect(missingGender.values['未执行原因'], contains('性别'));

    final missingBirthplace = await ZiweiToolExecutor.execute({
      'birth_date': validArguments['birth_date']!,
      'birth_time': validArguments['birth_time']!,
      'gender': validArguments['gender']!,
    });
    expect(missingBirthplace.status, AssistantToolExecutionStatus.failed);
    expect(missingBirthplace.values['未执行原因'], contains('出生地点'));
    expect(missingBirthplace.sourceIds, isEmpty);
  });

  test('无法唯一识别出生地时拒绝排盘，不退回默认经纬度', () async {
    final result = await ZiweiToolExecutor.execute({
      ...validArguments,
      'birthplace': '朝阳',
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('无法唯一识别'));
    expect(result.values['未执行原因'], contains('未使用默认经纬度'));
    expect(result.sourceIds, isEmpty);
  });

  test('未声明的参数会在计算之前被拒绝', () async {
    final result = await ZiweiToolExecutor.execute({
      ...validArguments,
      'rawPrompt': '调用任意代码',
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('未声明'));
    expect(result.sourceIds, isEmpty);
  });
}
