import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_tool_executor.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 14, 15, 12);

  test('App injects current local time and overwrites caller-supplied at', () {
    final prepared = ZiWuLiuZhuToolExecutor.prepareExecutionArguments(
      const {'at': '1980-01-01T00:00'},
      now: fixedNow,
    );
    expect(prepared['at'], '2026-11-14T15:12');
    final result = ZiWuLiuZhuToolExecutor.execute(prepared);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('ziwu_liuzhu'), isEmpty);
    expect(result.validateArgumentsMatch(prepared), isEmpty);
    expect(result.sourceIds, const [
      ZiWuLiuZhuToolExecutor.sourceId,
      ZiWuLiuZhuToolExecutor.referenceSourceId,
    ]);
  });

  test('explicit date and time are combined by App without changing their values', () {
    final prepared = ZiWuLiuZhuToolExecutor.prepareExecutionArguments(
      const {
        'date': '2026-10-08',
        'time': '12:00',
        'at': '1980-01-01T00:00',
      },
    );
    expect(prepared, const {
      'date': '2026-10-08',
      'time': '12:00',
      'at': '2026-10-08T12:00',
    });
    final result = ZiWuLiuZhuToolExecutor.execute(prepared);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('ziwu_liuzhu'), isEmpty);
    expect(result.validateArgumentsMatch(prepared), isEmpty);
    expect(result.values['日干支'], '乙卯');
    expect(result.values['时辰'], '午');
    expect(result.values['对应经络'], '心经');
    expect(result.values['纳子法本穴'], '少府');
    expect(result.values['计算口径'], contains('子时 23:00 换日'));
  });

  test('date-only requests remain incomplete and do not silently use today', () {
    const arguments = {'date': '2026-11-14'};
    final prepared =
        ZiWuLiuZhuToolExecutor.prepareExecutionArguments(arguments, now: fixedNow);
    expect(prepared.containsKey('at'), isFalse);
    expect(
      ZiWuLiuZhuToolExecutor.validateArguments(prepared),
      contains('缺少完整的设备本地日期和时间'),
    );
    final result = ZiWuLiuZhuToolExecutor.execute(prepared);
    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.sourceIds, isEmpty);
  });

  test('time-only requests use the App device-local calendar date', () {
    final prepared = ZiWuLiuZhuToolExecutor.prepareExecutionArguments(
      const {'time': '10:30'},
      now: fixedNow,
    );
    expect(prepared, const {
      'time': '10:30',
      'date': '2026-11-14',
      'at': '2026-11-14T10:30',
    });
    expect(
      ZiWuLiuZhuToolExecutor.execute(prepared).status,
      AssistantToolExecutionStatus.succeeded,
    );
  });

  test('invalid timestamps, mismatched slots, and undeclared fields fail closed', () {
    for (final arguments in [
      const {'at': '2026-02-30T10:30'},
      const {'at': '2026-11-14T10:30Z'},
      const {'at': '2026-11-14T10:30', 'date': '2026-11-15'},
      const {'at': '2026-11-14T10:30', 'time': '11:30'},
      const {'at': '2026-11-14T10:30', 'sex': 'female'},
    ]) {
      final result = ZiWuLiuZhuToolExecutor.execute(arguments);
      expect(result.status, AssistantToolExecutionStatus.failed,
          reason: arguments.toString());
      expect(result.sourceIds, isEmpty, reason: arguments.toString());
    }
  });
}
