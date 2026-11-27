import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/almanac_tool_executor.dart';

void main() {
  group('AlmanacToolExecutor', () {
    test('executes the existing local almanac engine for an explicit date', () {
      const arguments = {'date': '2026-11-12'};
      final result = AlmanacToolExecutor.execute(arguments);

      expect(result.status, AssistantToolExecutionStatus.succeeded);
      expect(result.toolId, 'almanac');
      expect(result.values['公历'], '2026-11-12');
      expect(result.values['星期'], isNotEmpty);
      expect(result.values['农历'], startsWith('农历'));
      expect(result.values['干支'], isNotEmpty);
      expect(result.values['建除'], isNotEmpty);
      expect(result.values['宜'], isNotEmpty);
      expect(result.values['忌'], isNotEmpty);
      expect(result.sourceIds, [AlmanacToolExecutor.sourceId]);
      expect(result.arguments, arguments);
      expect(result.disclaimer, contains('民俗文化参考'));
    });

    test('rejects impossible dates rather than normalizing them', () {
      final result = AlmanacToolExecutor.execute(
        const {'date': '2026-02-30'},
      );

      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.values['错误'], contains('有效日期'));
      expect(result.sourceIds, isEmpty);
      expect(result.arguments, const {'date': '2026-02-30'});
    });

    test('rejects dates outside the existing screen range', () {
      final result = AlmanacToolExecutor.execute(
        const {'date': '2101-01-01'},
      );

      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.values['错误'], contains('1900-2100'));
    });

    test('rejects undeclared arguments', () {
      final result = AlmanacToolExecutor.execute(
        const {'date': '2026-11-12', 'birthDate': '1983-01-01'},
      );

      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.values['错误'], contains('未声明'));
      expect(result.sourceIds, isEmpty);
    });
  });
}
