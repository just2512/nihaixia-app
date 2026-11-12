import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/yunqi_tool_executor.dart';

void main() {
  group('YunQiToolExecutor', () {
    test('executes the existing local engine with an explicit ISO date', () {
      final result = YunQiToolExecutor.execute(
        const {'date': '2026-11-12'},
        now: DateTime(2000, 1, 1),
      );

      expect(result.status, AssistantToolExecutionStatus.succeeded);
      expect(result.toolId, 'yunqi');
      expect(result.values['推算日期'], '2026-11-12');
      expect(result.values['运气年'], '丙午年（马）');
      expect(result.sourceIds, [YunQiToolExecutor.sourceId]);
      expect(result.arguments, const {'date': '2026-11-12'});
      expect(result.disclaimer, contains('不构成医疗建议'));
    });

    test('uses the injected clock only when the date argument is absent', () {
      final result = YunQiToolExecutor.execute(
        const {},
        now: DateTime(2024, 2, 29, 18),
      );

      expect(result.status, AssistantToolExecutionStatus.succeeded);
      expect(result.values['推算日期'], '2024-02-29');
      expect(result.arguments, isEmpty);
    });

    test('rejects impossible dates instead of silently falling back to today', () {
      final result = YunQiToolExecutor.execute(
        const {'date': '2026-02-30'},
        now: DateTime(2026, 11, 12),
      );

      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.values['错误'], contains('日期无效'));
      expect(result.sourceIds, isEmpty);
      expect(result.arguments, const {'date': '2026-02-30'});
    });

    test('rejects dates outside the page-supported range', () {
      final result = YunQiToolExecutor.execute(
        const {'date': '1899-12-31'},
      );

      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.values['错误'], contains('1900-2100'));
    });

    test('rejects undeclared arguments', () {
      final result = YunQiToolExecutor.execute(
        const {'date': '2026-11-12', 'prompt': 'do something else'},
      );

      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.values['错误'], contains('未声明'));
    });
  });
}
