import 'package:flutter_test/flutter_test.dart';
import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import 'package:nihaisha_app/data/huangdi_siji_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/huangdi_siji_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(HuangdiSijiData.ensureLoaded);

  test('Headless 结果复用原页面的公历转农历月、时辰映射与本地诗表', () async {
    const arguments = {
      'birth_date': '1990-01-02',
      'birth_time': '16:30',
    };

    final lunar = LunarDate.fromSolar(
      AstroDateTime(1990, 1, 2, 12, 0, 0),
    );
    const branches = [
      '子', '丑', '寅', '卯', '辰', '巳',
      '午', '未', '申', '酉', '戌', '亥',
    ];
    const hour = 16;
    final shiChen = branches[((hour.clamp(0, 23) + 1) ~/ 2) % 12];
    final expectedSeason = HuangdiSijiData.seasonOfLunarMonth(lunar.month);
    final expected = HuangdiSijiData.compute(lunar.month, shiChen);

    final result = await HuangdiSijiToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'huangdi_siji');
    expect(result.title, '轩辕黄帝四季歌');
    expect(result.validateFor('huangdi_siji'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.sourceIds, const [
      'local-engine:huangdi-siji',
      'local-data:huangdi-siji-ge',
    ]);
    expect(result.values['出生公历'], '1990-01-02 16:30');
    expect(result.values['农历月份'], lunar.month.toString());
    expect(result.values['季节口径'], expectedSeason);
    expect(result.values['出生时辰'], shiChen + '时');
    expect(result.values['对应部位'], expected.part);
    expect(result.values['命格标题'], expected.title);
    expect(result.values['部位诗'], expected.poem);
    expect(result.values['现有释义'], expected.interpretation);
    expect(result.values['季节边界说明'], HuangdiSijiData.seasonBasisNote);
    expect(result.disclaimer, isNotEmpty);
  });

  test('Headless 入口拒绝缺失/非法日期、时间及未声明参数', () async {
    final missingDate = await HuangdiSijiToolExecutor.execute(
      const {'birth_time': '08:30'},
    );
    expect(missingDate.status, AssistantToolExecutionStatus.failed);
    expect(missingDate.sourceIds, isEmpty);
    expect(missingDate.values['未执行原因'], contains('出生日期'));

    final missingTime = await HuangdiSijiToolExecutor.execute(
      const {'birth_date': '1990-01-02'},
    );
    expect(missingTime.status, AssistantToolExecutionStatus.failed);
    expect(missingTime.sourceIds, isEmpty);
    expect(missingTime.values['未执行原因'], contains('出生时间'));

    for (final invalidDate in ['1990-02-30', '1919-12-31', '2999-01-01']) {
      final result = await HuangdiSijiToolExecutor.execute({
        'birth_date': invalidDate,
        'birth_time': '08:30',
      });
      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.sourceIds, isEmpty);
      expect(result.values['未执行原因'], contains('出生日期'));
    }

    final invalidTime = await HuangdiSijiToolExecutor.execute(
      const {
        'birth_date': '1990-01-02',
        'birth_time': '24:00',
      },
    );
    expect(invalidTime.status, AssistantToolExecutionStatus.failed);
    expect(invalidTime.values['未执行原因'], contains('出生时间'));

    final unknownArgument = await HuangdiSijiToolExecutor.execute(
      const {
        'birth_date': '1990-01-02',
        'birth_time': '08:30',
        'gender': 'male',
      },
    );
    expect(unknownArgument.status, AssistantToolExecutionStatus.failed);
    expect(unknownArgument.sourceIds, isEmpty);
    expect(unknownArgument.values['未执行原因'], contains('未声明'));
  });
}
