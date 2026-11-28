import 'package:flutter_test/flutter_test.dart';
import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart' show AstroDateTime, LunarDate;
import 'package:nihaisha_app/data/xiaoliuren_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/xiaoliuren_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const arguments = {
    'date': '2026-11-14',
    'hour': '午时',
    'rule': 'common',
  };

  test('Headless 结果与页面现有正午农历换算及纯函数排课一致', () async {
    final result = await XiaoliurenToolExecutor.execute(arguments);
    final lunar = LunarDate.fromSolar(
      AstroDateTime(2026, 11, 14, 12, 0, 0),
    );
    final expected = computeXiaoliuren(
      lunarMonth: lunar.month,
      lunarDay: lunar.day,
      hourNumber: 7,
      rule: XiaoliurenRule.common,
    );

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'xiaoliuren');
    expect(result.validateFor('xiaoliuren'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.sourceIds, const [
      XiaoliurenToolExecutor.sourceId,
      XiaoliurenToolExecutor.ruleDataSourceId,
    ]);
    expect(result.values['公历日期'], '2026-11-14');
    expect(result.values['农历月日'],
        '${expected.lunarMonth}月${expected.lunarDay}日');
    expect(result.values['时辰'], '午时');
    expect(result.values['起课口径'], XiaoliurenRule.common.label);
    expect(result.values['月宫'], expected.month.palace.name);
    expect(result.values['月宫顺数步数'], expected.month.steps.toString());
    expect(result.values['日宫'], expected.day.palace.name);
    expect(result.values['日宫顺数步数'], expected.day.steps.toString());
    expect(result.values['正时主断'], expected.hour.palace.name);
    expect(result.values['正时主事'], expected.hour.palace.deity);
    expect(result.values['正时顺数步数'], expected.hour.steps.toString());
    expect(result.values['正时歌诀'],
        xiaoliurenVerse(expected.hour.palace, XiaoliurenRule.common));
    expect(result.disclaimer, contains('民俗文化参考'));
  });

  test('可选择多能鄙事口径，不把两种算法口径合并或伪装成唯一传统', () async {
    const alternative = {
      'date': '2026-11-14',
      'hour': '午时',
      'rule': 'duoneng',
    };
    final result = await XiaoliurenToolExecutor.execute(alternative);
    final lunar = LunarDate.fromSolar(
      AstroDateTime(2026, 11, 14, 12, 0, 0),
    );
    final expected = computeXiaoliuren(
      lunarMonth: lunar.month,
      lunarDay: lunar.day,
      hourNumber: 7,
      rule: XiaoliurenRule.duoneng,
    );

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateArgumentsMatch(alternative), isEmpty);
    expect(result.values['起课口径'], XiaoliurenRule.duoneng.label);
    expect(result.values['口径说明'], XiaoliurenRule.duoneng.source);
    expect(result.values['日宫'], expected.day.palace.name);
    expect(result.values['日宫顺数步数'], expected.day.steps.toString());
    expect(result.values['正时主断'], expected.hour.palace.name);
    expect(result.sourceIds, contains(XiaoliurenToolExecutor.ruleDataSourceId));
  });

  test('未选择起课口径时拒绝执行，不替用户默认选择通行掌诀', () async {
    final result = await XiaoliurenToolExecutor.execute({
      'date': arguments['date']!,
      'hour': arguments['hour']!,
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('缺少起课口径'));
    expect(result.sourceIds, isEmpty);
  });

  test('拒绝无效日期、越界日期和缺失时辰', () async {
    final invalidDate = await XiaoliurenToolExecutor.execute({
      ...arguments,
      'date': '2026-02-30',
    });
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('公历日期'));

    final tooEarly = await XiaoliurenToolExecutor.execute({
      ...arguments,
      'date': '1919-12-31',
    });
    expect(tooEarly.status, AssistantToolExecutionStatus.failed);
    expect(tooEarly.values['未执行原因'], contains('超出页面支持范围'));

    final missingHour = await XiaoliurenToolExecutor.execute({
      'date': arguments['date']!,
    });
    expect(missingHour.status, AssistantToolExecutionStatus.failed);
    expect(missingHour.values['未执行原因'], contains('时辰'));
    expect(missingHour.sourceIds, isEmpty);
  });

  test('拒绝未声明参数和无效口径', () async {
    final unknown = await XiaoliurenToolExecutor.execute({
      ...arguments,
      'rawPrompt': '请自行编造一个吉凶结果',
    });
    expect(unknown.status, AssistantToolExecutionStatus.failed);
    expect(unknown.values['未执行原因'], contains('未声明'));
    expect(unknown.sourceIds, isEmpty);

    final invalidRule = await XiaoliurenToolExecutor.execute({
      ...arguments,
      'rule': 'invented',
    });
    expect(invalidRule.status, AssistantToolExecutionStatus.failed);
    expect(invalidRule.values['未执行原因'], contains('口径无效'));
    expect(invalidRule.sourceIds, isEmpty);
  });
}
