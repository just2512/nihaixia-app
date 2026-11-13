import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import 'package:nihaisha_app/data/meihua_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/bazi_service.dart' show computeBaZiPaipan;
import 'package:nihaisha_app/services/meihua_tool_executor.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 13, 18);
  const numberArguments = {
    'method': 'number',
    'first': '3',
    'second': '7',
    'date': '2026-11-13',
  };

  LunarDate lunarFor(String date) {
    final parsed = DateTime.parse(date);
    return LunarDate.fromSolar(
      AstroDateTime(parsed.year, parsed.month, parsed.day, 12, 0, 0),
    );
  }

  test('数字起卦复用原算法并返回完整结构化结果与来源', () {
    final result = MeihuaToolExecutor.execute(
      numberArguments,
      now: fixedNow,
    );
    final lunar = lunarFor('2026-11-13');
    final expected = computeMeihuaByNumber(
      first: 3,
      second: 7,
      lunarMonth: lunar.month,
    );

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'meihua');
    expect(result.title, '梅花易数数字起卦');
    expect(result.validateFor('meihua'), isEmpty);
    expect(result.validateArgumentsMatch(numberArguments), isEmpty);
    expect(result.sourceIds, [
      MeihuaToolExecutor.sourceId,
      MeihuaToolExecutor.dataSourceId,
    ]);
    expect(result.arguments, numberArguments);
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

  test('时间起卦复用页面相同的年支、时支和公历正午农历转换口径', () {
    const arguments = {
      'method': 'time',
      'date': '2026-11-13',
      'hour_branch': '申',
    };
    final result = MeihuaToolExecutor.execute(arguments, now: fixedNow);
    final lunar = lunarFor('2026-11-13');
    final bazi = computeBaZiPaipan(
      DateTime(2026, 11, 13, 16),
      useTrueSolarTime: false,
      ratHourMode: false,
    );
    final branches = MeihuaToolExecutor.earthlyBranches;
    final expected = computeMeihuaByTime(
      yearZhiIndex: branches.indexOf(bazi.zhis[0]) + 1,
      lunarMonth: lunar.month,
      lunarDay: lunar.day,
      hourZhiIndex: branches.indexOf(bazi.zhis[3]) + 1,
    );

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('meihua'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.values['起卦方式'], '时间起卦');
    expect(result.values['起卦时辰'], '申时');
    expect(result.values['主卦'], '第${expected.main.seq}卦 ${expected.main.name}');
    expect(result.values['互卦'], '第${expected.mutual.seq}卦 ${expected.mutual.name}');
    expect(result.values['变卦'], '第${expected.changed.seq}卦 ${expected.changed.name}');
    expect(result.values['动爻'], '第${expected.movingYao}爻');
    expect(result.values['推算过程'], expected.trace.join('；'));
  });

  test('时间起卦缺省时辰沿用 App 页面当前本地时辰', () {
    final result = MeihuaToolExecutor.execute(
      const {'method': 'time', 'date': '2026-11-13'},
      now: fixedNow,
    );
    final branchIndex = ((fixedNow.hour + 1) ~/ 2) % 12;
    final branch = MeihuaToolExecutor.earthlyBranches[branchIndex];

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.values['起卦时辰'], '$branch时');
    expect(result.arguments['hour_branch'], branch);
  });

  test('随机起卦由 App 本地随机数生成，并可用注入随机源稳定复核', () {
    const arguments = {'method': 'random', 'date': '2026-11-13'};
    final lunar = lunarFor('2026-11-13');
    final expected = computeMeihuaByRandom(
      lunarMonth: lunar.month,
      rng: Random(17),
    );
    final result = MeihuaToolExecutor.execute(
      arguments,
      now: fixedNow,
      rng: Random(17),
    );

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('meihua'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.values['起卦方式'], '随机起卦');
    expect(result.values['主卦'], '第${expected.main.seq}卦 ${expected.main.name}');
    expect(result.values['互卦'], '第${expected.mutual.seq}卦 ${expected.mutual.name}');
    expect(result.values['变卦'], '第${expected.changed.seq}卦 ${expected.changed.name}');
    expect(result.values['动爻'], '第${expected.movingYao}爻');
    expect(result.values['推算过程'], expected.trace.join('；'));
  });

  test('数字起卦缺少数字、日期无效、数字越界或方法字段错误时拒绝执行', () {
    final missing = MeihuaToolExecutor.execute(
      const {'method': 'number', 'first': '3', 'date': '2026-11-13'},
      now: fixedNow,
    );
    expect(missing.status, AssistantToolExecutionStatus.failed);
    expect(missing.sourceIds, isEmpty);
    expect(missing.values['未执行原因'], contains('缺少'));

    final invalidDate = MeihuaToolExecutor.execute({
      ...numberArguments,
      'date': '2026-02-30',
    }, now: fixedNow);
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('日期无效'));

    final invalidNumber = MeihuaToolExecutor.execute({
      ...numberArguments,
      'first': '0',
    }, now: fixedNow);
    expect(invalidNumber.status, AssistantToolExecutionStatus.failed);
    expect(invalidNumber.values['未执行原因'], contains('正整数'));

    final futureDate = MeihuaToolExecutor.execute({
      ...numberArguments,
      'date': '2028-01-01',
    }, now: fixedNow);
    expect(futureDate.status, AssistantToolExecutionStatus.failed);
    expect(futureDate.values['未执行原因'], contains('一年内'));

    final missingMethod = MeihuaToolExecutor.execute(
      const {'first': '3', 'second': '7', 'date': '2026-11-13'},
      now: fixedNow,
    );
    expect(missingMethod.status, AssistantToolExecutionStatus.failed);
    expect(missingMethod.values['未执行原因'], contains('起卦方式'));
  });

  test('时间与随机起卦拒绝混入其他方法的参数', () {
    final timeWithNumber = MeihuaToolExecutor.execute(
      const {
        'method': 'time',
        'first': '3',
        'date': '2026-11-13',
      },
      now: fixedNow,
    );
    expect(timeWithNumber.status, AssistantToolExecutionStatus.failed);
    expect(timeWithNumber.sourceIds, isEmpty);

    final randomWithBranch = MeihuaToolExecutor.execute(
      const {
        'method': 'random',
        'date': '2026-11-13',
        'hour_branch': '申',
      },
      now: fixedNow,
    );
    expect(randomWithBranch.status, AssistantToolExecutionStatus.failed);
    expect(randomWithBranch.sourceIds, isEmpty);

    final invalidBranch = MeihuaToolExecutor.execute(
      const {
        'method': 'time',
        'date': '2026-11-13',
        'hour_branch': '不存在',
      },
      now: fixedNow,
    );
    expect(invalidBranch.status, AssistantToolExecutionStatus.failed);
    expect(invalidBranch.values['未执行原因'], contains('时辰无效'));
  });

  test('农历文本不会被当成公历，缺省日期按执行设备的本地日期回显', () {
    final unknown = MeihuaToolExecutor.execute({
      ...numberArguments,
      'rawPrompt': '请模型自行推断',
    }, now: fixedNow);
    expect(unknown.status, AssistantToolExecutionStatus.failed);
    expect(unknown.sourceIds, isEmpty);
    expect(unknown.values['未执行原因'], contains('未声明'));

    final noDate = MeihuaToolExecutor.execute(
      const {'method': 'number', 'first': '3', 'second': '7'},
      now: fixedNow,
    );
    expect(noDate.status, AssistantToolExecutionStatus.succeeded);
    expect(noDate.arguments['date'], '2026-11-13');
    expect(noDate.values['公历日期'], '2026-11-13');
  });
}
