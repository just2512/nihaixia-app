import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/dosage_tool_executor.dart';

void main() {
  test('汉制重量换算返回 App 结果、原始参数和来源 ID', () {
    const arguments = {
      'amount': '1.5',
      'unit': '两',
      'standard': 'han',
    };
    final result = DosageToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('dosage'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.values['换算类别'], '重量');
    expect(result.values['度量标准'], '汉制');
    expect(result.values['换算结果'], '23.438 克');
    expect(result.values['目标单位'], '克');
    expect(result.sourceIds, const [
      DosageToolExecutor.sourceId,
      DosageToolExecutor.dataSourceId,
    ]);
    expect(result.disclaimer, contains('不是中药处方'));
    expect(result.values.keys, isNot(contains('处方')));
  });

  test('容量和长度换算不要求无关的重量标准', () {
    final volume = DosageToolExecutor.execute(const {
      'amount': '1',
      'unit': '升',
    });
    final length = DosageToolExecutor.execute(const {
      'amount': '2',
      'unit': '尺',
    });

    expect(volume.status, AssistantToolExecutionStatus.succeeded);
    expect(volume.values['换算结果'], '200 毫升');
    expect(volume.values['度量标准'], contains('不适用'));
    expect(length.status, AssistantToolExecutionStatus.succeeded);
    expect(length.values['换算结果'], '46.2 厘米');
  });

  test('重量换算缺少标准时 fail closed', () {
    final result = DosageToolExecutor.execute(const {
      'amount': '1',
      'unit': '两',
    });
    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.sourceIds, isEmpty);
    expect(result.values['未执行原因'], contains('汉制、台制或唐制'));
  });

  test('无效输入、标准冲突、单位不适配和额外参数均不执行', () {
    final cases = [
      const {'amount': '0', 'unit': '两', 'standard': 'han'},
      const {'amount': 'NaN', 'unit': '两', 'standard': 'han'},
      const {'amount': '1', 'unit': '铢', 'standard': 'tai'},
      const {'amount': '1', 'unit': '两', 'standard': 'other'},
      const {'amount': '1', 'unit': '两', 'standard': 'han', 'formula': 'xxx'},
    ];
    for (final arguments in cases) {
      final result = DosageToolExecutor.execute(arguments);
      expect(result.status, AssistantToolExecutionStatus.failed,
          reason: arguments.toString());
      expect(result.sourceIds, isEmpty);
    }
  });
}
