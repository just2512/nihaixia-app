import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/yuxiaji_omen_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/yuxiaji_omen_time.dart';
import 'package:nihaisha_app/services/yuxiaji_omen_tool_executor.dart';

void main() {
  test('按 App 本机时辰返回本地《玉匣记》条目和真实来源', () {
    final now = DateTime(2026, 11, 16, 0, 30);
    final result = YuxiajiOmenToolExecutor.execute(
      const {},
      clock: () => now,
    );

    expect(result.toolId, 'yuxiaji_omen');
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('yuxiaji_omen'), isEmpty);
    expect(result.validateArgumentsMatch(const {}), isEmpty);
    expect(result.arguments, isEmpty);
    expect(result.sourceIds, [YuxiajiOmenToolExecutor.sourceId]);
    expect(result.values['App 本机日期时间'], now.toIso8601String());
    expect(result.values['当前时辰'], '子时 23:00–00:59');
    expect(
      result.values['《玉匣记》当前时辰身兆条目'],
      contains(kYuXiaJiShiChenOmens.first.duanByHour[0]),
    );
    expect(result.values['数据范围'], contains('不包含需要额外观察输入'));
    expect(result.disclaimer, contains('不是医学诊断'));
  });

  test('时辰边界沿用原页面的 23 点起算口径', () {
    expect(shiChenIndexOf(DateTime(2026, 1, 1, 0, 59)), 0);
    expect(shiChenIndexOf(DateTime(2026, 1, 1, 1, 0)), 1);
    expect(shiChenIndexOf(DateTime(2026, 1, 1, 22, 59)), 11);
    expect(shiChenIndexOf(DateTime(2026, 1, 1, 23, 0)), 0);
  });

  test('Headless 入口拒绝未声明参数，不产生成功来源', () {
    final result = YuxiajiOmenToolExecutor.execute(
      const {'hour': '子'},
      clock: () => DateTime(2026, 11, 16, 0, 30),
    );

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.sourceIds, isEmpty);
    expect(result.validateFor('yuxiaji_omen'), isEmpty);
    expect(result.values['未执行原因'], contains('不接受额外参数'));
  });
}
