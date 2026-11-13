import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sxwnl_spa_dart/sxwnl_spa_dart.dart'
    show AstroDateTime, LunarDate;

import 'package:nihaisha_app/data/chenggu_data.dart';
import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/bazi_service.dart' show computeBaZiPaipan;
import 'package:nihaisha_app/services/chenggu_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = SettingsRepository.instance;
    if (!settings.isLoaded) await settings.load();
    await ChengguData.ensureLoaded();
  });

  test('称骨 Headless 执行与原页面使用同一八字/历法/称骨算法和设置', () async {
    const arguments = {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
    };
    final settings = SettingsRepository.instance;
    final solar = DateTime(1990, 1, 2, 8, 30);
    final chart = computeBaZiPaipan(
      solar,
      useTrueSolarTime: settings.useTrueSolarTime,
      ratHourMode: settings.distinguishZiShiEnabled,
    );
    final lunar = LunarDate.fromSolar(
      AstroDateTime(1990, 1, 2, 12, 0, 0),
    );
    final expected = ChengguData.compute(
      chart.gans[0] + chart.zhis[0],
      lunar.month,
      lunar.day,
      chart.zhis[3],
    );

    final result = await ChengguToolExecutor.execute(arguments);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'chenggu');
    expect(result.title, '袁天罡称骨');
    expect(result.validateFor('chenggu'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.sourceIds, const [
      'local-engine:chenggu',
      'local-data:chenggu-bone-weight',
    ]);
    expect(result.arguments, arguments);
    expect(result.values['出生公历'], '1990-01-02 08:30');
    expect(
      result.values['出生农历口径'],
      contains(lunar.month.toString() + '月' + lunar.day.toString() + '日'),
    );
    expect(result.values['称骨计算时柱地支'], chart.zhis[3]);
    expect(result.values['真太阳时校正'],
        settings.useTrueSolarTime ? '开启' : '关闭');
    expect(result.values['早晚子时区分'],
        settings.distinguishZiShiEnabled ? '开启' : '关闭');
    expect(
      result.values['总骨重'],
      expected.liang.toString() + '两' + expected.qian.toString() +
          '钱（' + expected.totalQian.toString() + '钱）',
    );
    expect(result.values['称骨歌诀'], expected.poem);
    expect(result.values['称骨歌诀标题'], expected.title);
    expect(result.values['称骨说明'], expected.detail);
    expect(result.disclaimer, isNotEmpty);
  });

  test('称骨拒绝缺失/非法出生日期、出生时间和未声明参数', () async {
    final missingDate = await ChengguToolExecutor.execute(
      const {'birth_time': '08:30'},
    );
    expect(missingDate.status, AssistantToolExecutionStatus.failed);
    expect(missingDate.sourceIds, isEmpty);
    expect(missingDate.values['未执行原因'], contains('出生日期'));

    final missingTime = await ChengguToolExecutor.execute(
      const {'birth_date': '1990-01-02'},
    );
    expect(missingTime.status, AssistantToolExecutionStatus.failed);
    expect(missingTime.sourceIds, isEmpty);
    expect(missingTime.values['未执行原因'], contains('出生时间'));

    final invalidDate = await ChengguToolExecutor.execute(
      const {
        'birth_date': '1990-02-30',
        'birth_time': '08:30',
      },
    );
    expect(invalidDate.status, AssistantToolExecutionStatus.failed);
    expect(invalidDate.values['未执行原因'], contains('出生日期'));

    final futureDate = await ChengguToolExecutor.execute(
      const {
        'birth_date': '2999-01-01',
        'birth_time': '08:30',
      },
    );
    expect(futureDate.status, AssistantToolExecutionStatus.failed);
    expect(futureDate.values['未执行原因'], contains('出生日期'));

    final invalidTime = await ChengguToolExecutor.execute(
      const {
        'birth_date': '1990-01-02',
        'birth_time': '25:90',
      },
    );
    expect(invalidTime.status, AssistantToolExecutionStatus.failed);
    expect(invalidTime.values['未执行原因'], contains('出生时间'));

    final unknownArgument = await ChengguToolExecutor.execute(
      const {
        'birth_date': '1990-01-02',
        'birth_time': '08:30',
        'guess': '12:00',
      },
    );
    expect(unknownArgument.status, AssistantToolExecutionStatus.failed);
    expect(unknownArgument.values['未执行原因'], contains('未声明'));
    expect(unknownArgument.sourceIds, isEmpty);
  });
}
