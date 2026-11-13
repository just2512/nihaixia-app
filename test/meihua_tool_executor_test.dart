import 'package:flutter_test/flutter_test.dart';
import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import 'package:nihaisha_app/data/meihua_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/meihua_tool_executor.dart';

void main() {
  const validArguments = {
    'first': '3',
    'second': '7',
    'date': '2026-11-13',
  };
  final fixedNow = DateTime(2026, 11, 13, 18);

  test('数字梅花 Headless 复用原页面算法并返回完整结构化结果与来源', () {
    final result = MeihuaToolExecutor.execute(
      validArguments,
      now: fixedNow,
    );
    final lunar = LunarDate.fromSolar(
      AstroDateTime(2026, 11, 13, 12, 0, 0),
    );
    final expected = computeMeihuaByNumber(
      first: 3,
      second: 7,
      lunarMonth: lunar.month,
    );

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'meihua');
    expect(result.validateFor('meihua'), isEmpty);
    expect(result.validateArgumentsMatch(validArguments), isEmpty);
    expect(result.sourceIds, [
      MeihuaToolExecutor.sourceId,
      MeihuaToolExecutor.dataSourceId,
    ]);
    expect(result.arguments, validArguments);
    expect(result.values['公历日期'], '2026-11-13');
    expect(result.values['农历月份'], '${lunar.month}月');
    expect(result.values['第一数（上卦）'], '3');
    expect(result.values['第二数（下卦）'], '7');
    expect(result.values['主卦'], '第${expected.main.seq}卦 ${expected.main.name}');
    expect(result.values['主卦卦辞'], expected.main.judgement);
    expect(result.values['互卦'], '第${expected.mutual.seq}卦 ${expected.mutual.name}');
    expect(result.values['变卦'], '第${expected.changed.seq}卦 ${expected.changed.name}');
    expect(result.values['动爻'], '第${expected.movingYao}爻');
    expect(result.values['动爻爻辞'], expected.movingYaoCi);
    expect(result.values['体用关系'], expected.mainRelation.label);
    expect(result.values['体卦旺衰'], expected.tiWangShuai.label);
    expect(result.values['推算过程'], expected.trace.join('；'));
    expect(result.disclaimer, contains('传统民俗文化学习参考'));
  });

  test('缺少任一数字、日期无效或显式越界时拒绝执行', () {
    final missing = MeihuaToolExecutor.execute({
      'first': '3',
      'date': '2026-11-13',
    }, now: fixedNow);
    expect(missing.status, AssistantToolExecutionStatus.failed);
    expect(missing.sourceIds, isEmpty);
    expect(missing.values['未执行原因'], contains('缺少'));

    final invalidDate = MeihuaToolExecutor.execute({
      ...validArguments,
      'date': '2026-02-30',
    }, now: fixedNow);
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('日期无效'));

    final invalidNumber = MeihuaToolExecutor.execute({
      ...validArguments,
      'first': '0',
    }, now: fixedNow);
    expect(invalidNumber.status, AssistantToolExecutionStatus.failed);
    expect(invalidNumber.values['未执行原因'], contains('正整数'));

    final futureDate = MeihuaToolExecutor.execute({
      ...validArguments,
      'date': '2028-01-01',
    }, now: fixedNow);
    expect(futureDate.status, AssistantToolExecutionStatus.failed);
    expect(futureDate.values['未执行原因'], contains('一年内'));
  });

  test('未声明参数和缺失的公历日期不应产生计算结果', () {
    final unknown = MeihuaToolExecutor.execute({
      ...validArguments,
      'rawPrompt': '请模型自行推断',
    }, now: fixedNow);
    expect(unknown.status, AssistantToolExecutionStatus.failed);
    expect(unknown.sourceIds, isEmpty);
    expect(unknown.values['未执行原因'], contains('未声明'));

    final missingDate = MeihuaToolExecutor.execute({
      'first': '3',
      'second': '7',
    }, now: fixedNow);
    expect(missingDate.status, AssistantToolExecutionStatus.failed);
    expect(missingDate.values['未执行原因'], contains('公历 YYYY-MM-DD'));
  });
}
