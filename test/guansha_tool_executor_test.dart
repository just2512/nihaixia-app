import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/guansha_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validArguments = {
    'birth_date': '1990-01-02',
    'birth_time': '08:30',
    'gender': 'male',
    'birthplace': '上海市',
  };

  test('小儿关煞 Headless 执行复用本地八字与关煞规则并返回来源', () async {
    final result = await GuanshaToolExecutor.execute(validArguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'guansha');
    expect(result.validateFor('guansha'), isEmpty);
    expect(result.validateArgumentsMatch(validArguments), isEmpty);
    expect(result.arguments, validArguments);
    expect(result.sourceIds, const [
      GuanshaToolExecutor.sourceId,
      GuanshaToolExecutor.dataSourceId,
      GuanshaToolExecutor.locationSourceId,
    ]);
    expect(result.values['出生地点'], contains('上海'));
    expect(result.values['出生地坐标'], contains('东经'));
    expect(result.values['出生农历'], isNotEmpty);
    expect(result.values['四柱'], isNotEmpty);
    expect(result.values['关煞命中数量'], isNotEmpty);
    expect(result.values['本地规则结果'], isNotEmpty);
    expect(result.values['规则库范围'], contains('36 关与 18 条扩展煞'));
    expect(result.disclaimer, contains('非医学结论'));
    expect(result.disclaimer, contains('不得据此延误就医'));
  });

  test('不接受无效日期、时刻或缺失性别，不使用页面默认值', () async {
    final invalidDate = await GuanshaToolExecutor.execute({
      ...validArguments,
      'birth_date': '1990-02-30',
    });
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('出生日期'));

    final invalidTime = await GuanshaToolExecutor.execute({
      ...validArguments,
      'birth_time': '25:90',
    });
    expect(invalidTime.status, AssistantToolExecutionStatus.failed);
    expect(invalidTime.values['未执行原因'], contains('出生时间'));

    final missingGender = await GuanshaToolExecutor.execute({
      'birth_date': validArguments['birth_date']!,
      'birth_time': validArguments['birth_time']!,
      'birthplace': validArguments['birthplace']!,
    });
    expect(missingGender.status, AssistantToolExecutionStatus.failed);
    expect(missingGender.values['未执行原因'], contains('性别'));
  });

  test('无法唯一识别出生地时拒绝测算，不回退默认经纬度', () async {
    final result = await GuanshaToolExecutor.execute({
      ...validArguments,
      'birthplace': '朝阳',
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('无法唯一识别'));
    expect(result.values['未执行原因'], contains('未使用默认经纬度'));
    expect(result.sourceIds, isEmpty);
  });

  test('超出原页面日期范围或传入未声明参数时在执行前拒绝', () async {
    final oldDate = await GuanshaToolExecutor.execute({
      ...validArguments,
      'birth_date': '1919-12-31',
    });
    expect(oldDate.status, AssistantToolExecutionStatus.failed);
    expect(oldDate.values['未执行原因'], contains('1920 年至今天'));

    final futureDate = DateTime.now().add(const Duration(days: 1));
    final future = await GuanshaToolExecutor.execute({
      ...validArguments,
      'birth_date':
          '${futureDate.year.toString().padLeft(4, '0')}-'
          '${futureDate.month.toString().padLeft(2, '0')}-'
          '${futureDate.day.toString().padLeft(2, '0')}',
    });
    expect(future.status, AssistantToolExecutionStatus.failed);
    expect(future.values['未执行原因'], contains('1920 年至今天'));

    final unexpected = await GuanshaToolExecutor.execute({
      ...validArguments,
      'rawPrompt': '不得作为额外排盘参数执行',
    });
    expect(unexpected.status, AssistantToolExecutionStatus.failed);
    expect(unexpected.values['未执行原因'], contains('未声明'));
    expect(unexpected.sourceIds, isEmpty);
  });
}
