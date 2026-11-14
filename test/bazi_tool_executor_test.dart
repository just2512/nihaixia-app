import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/bazi_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validArguments = {
    'birth_date': '1990-01-02',
    'birth_time': '08:30',
    'gender': 'male',
    'birthplace': '上海市',
  };

  test('八字 Headless 执行复用本地引擎并返回完整结果与来源', () async {
    final result = await BaziToolExecutor.execute(validArguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'bazi');
    expect(result.validateFor('bazi'), isEmpty);
    expect(result.validateArgumentsMatch(validArguments), isEmpty);
    expect(result.sourceIds, [
      BaziToolExecutor.sourceId,
      BaziToolExecutor.locationSourceId,
    ]);
    expect(result.values['出生地坐标'], contains('东经'));
    expect(result.values['完整排盘结果'], contains('四柱：'));
    expect(result.values['完整排盘结果'], contains('1990-01-02 08:30'));
    expect(result.disclaimer, contains('不另做历史时区或夏令时换算'));
  });

  test('不接受无效日期、时刻或缺失性别，不使用页面默认值', () async {
    final invalidDate = await BaziToolExecutor.execute({
      ...validArguments,
      'birth_date': '1990-02-30',
    });
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('出生日期'));

    final invalidTime = await BaziToolExecutor.execute({
      ...validArguments,
      'birth_time': '25:90',
    });
    expect(invalidTime.status, AssistantToolExecutionStatus.failed);
    expect(invalidTime.values['未执行原因'], contains('出生时间'));

    final missingGender = await BaziToolExecutor.execute({
      'birth_date': validArguments['birth_date']!,
      'birth_time': validArguments['birth_time']!,
      'birthplace': validArguments['birthplace']!,
    });
    expect(missingGender.status, AssistantToolExecutionStatus.failed);
    expect(missingGender.values['未执行原因'], contains('性别'));
  });

  test('无法唯一识别出生地时拒绝排盘，不退回默认经纬度', () async {
    final result = await BaziToolExecutor.execute({
      ...validArguments,
      'birthplace': '朝阳',
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('无法唯一识别'));
    expect(result.values['未执行原因'], contains('未使用默认经纬度'));
    expect(result.sourceIds, isEmpty);
  });

  test('未声明的参数会在计算之前被拒绝', () async {
    final result = await BaziToolExecutor.execute({
      ...validArguments,
      'rawPrompt': '调用任意代码',
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('未声明'));
    expect(result.sourceIds, isEmpty);
  });
  test('出生地点共享唯一解析器仍拒绝同名朝阳，不退回默认经纬度', () async {
    final ambiguous = await BaziToolExecutor.execute({
      ...validArguments,
      'birthplace': '朝阳',
    });
    expect(ambiguous.status, AssistantToolExecutionStatus.failed);
    expect(ambiguous.values['未执行原因'], contains('无法唯一识别'));
    expect(ambiguous.values['未执行原因'], contains('未使用默认经纬度'));
    expect(ambiguous.sourceIds, isEmpty);
  });

}
