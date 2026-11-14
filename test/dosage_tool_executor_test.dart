import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/dosage_tool_executor.dart';

void main() {
  test('successful weight conversion returns validated App result and source IDs', () {
    const arguments = {
      'standard': 'han',
      'value': '1',
      'unit': '两',
    };
    final result = DosageToolExecutor.execute(arguments);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('dosage'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.values['换算结果'], '15.625');
    expect(result.values['目标单位'], '克');
    expect(result.values['度量标准'], '汉制');
    expect(result.values['业务范围'], '仅单位换算；不计算药物处方剂量');
    expect(result.sourceIds, const [
      DosageToolExecutor.sourceId,
      DosageToolExecutor.factorsSourceId,
    ]);
    expect(result.disclaimer, contains('不构成临床剂量'));
  });

  test('volume/length conversion does not require a weight standard', () {
    const volume = {'value': '1', 'unit': '升'};
    final volumeResult = DosageToolExecutor.execute(volume);
    expect(volumeResult.status, AssistantToolExecutionStatus.succeeded);
    expect(volumeResult.values['换算结果'], '200');
    expect(volumeResult.values['目标单位'], '毫升');
    expect(volumeResult.validateArgumentsMatch(volume), isEmpty);

    const length = {'value': '1', 'unit': '尺'};
    final lengthResult = DosageToolExecutor.execute(length);
    expect(lengthResult.status, AssistantToolExecutionStatus.succeeded);
    expect(lengthResult.values['换算结果'], '23.1');
    expect(lengthResult.values['目标单位'], '厘米');
  });

  test('unsupported standards, units, non-positive and non-finite numbers fail closed', () {
    for (final arguments in [
      const {'value': '1', 'unit': '两'},
      const {'standard': 'taiwan', 'value': '1', 'unit': '铢'},
      const {'standard': 'tang', 'value': '1', 'unit': '石'},
      const {'standard': 'han', 'value': '0', 'unit': '两'},
      const {'standard': 'han', 'value': '-1', 'unit': '两'},
      const {'standard': 'han', 'value': 'NaN', 'unit': '两'},
      const {'standard': 'han', 'value': '1e309', 'unit': '两'},
      const {'standard': 'han', 'value': '1', 'unit': '克'},
    ]) {
      final result = DosageToolExecutor.execute(arguments);
      expect(result.status, AssistantToolExecutionStatus.failed,
          reason: arguments.toString());
      expect(result.sourceIds, isEmpty);
      expect(result.validateFor('dosage'), isEmpty);
      expect(result.validateArgumentsMatch(arguments), isEmpty);
    }
  });

  test('undeclared arguments never enter the calculation', () {
    final result = DosageToolExecutor.execute(const {
      'standard': 'han',
      'value': '1',
      'unit': '两',
      'dose_advice': '给病人服用',
    });
    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.sourceIds, isEmpty);
  });
}
