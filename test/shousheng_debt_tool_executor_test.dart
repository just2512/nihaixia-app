import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/data/shousheng_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/bazi_service.dart' show computeBaZiPaipan;
import 'package:nihaisha_app/services/shousheng_debt_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = SettingsRepository.instance;
    if (!settings.isLoaded) await settings.load();
    await ShoushengData.ensureLoaded();
  });

  test('禄库受生经执行复用原八字设置和本地生肖数据', () async {
    const arguments = {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'method': 'luku',
    };
    final settings = SettingsRepository.instance;
    final chart = computeBaZiPaipan(
      DateTime(1990, 1, 2, 8, 30),
      useTrueSolarTime: settings.useTrueSolarTime,
      ratHourMode: settings.distinguishZiShiEnabled,
    );
    final expected = ShoushengData.computeLuku(chart.zhis[0]);

    final result = await ShoushengDebtToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'shousheng_debt');
    expect(result.title, '受生债查询');
    expect(result.validateFor('shousheng_debt'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.sourceIds, const [
      ShoushengDebtToolExecutor.sourceId,
      ShoushengDebtToolExecutor.lukuDataSourceId,
    ]);
    expect(result.values['出生公历'], '1990-01-02 08:30');
    expect(result.values['查询体系'], '禄库受生经');
    expect(result.values['年支'], chart.zhis[0]);
    expect(result.values['日干'], chart.gans[2]);
    expect(result.values['时支'], chart.zhis[3]);
    expect(result.values['禄库曹官数据'], isNotEmpty);
    expect(result.values['本命元辰数据'], isNotEmpty);
    expect(result.values['禄库曹官数据'], contains(expected.warehouse['ku_no'].toString()));
    expect(result.values['本命元辰数据'], contains(expected.yuanchen['yuanchen'].toString()));
    expect(result.values['真太阳时校正'],
        settings.useTrueSolarTime ? '开启' : '关闭');
    expect(result.values['早晚子时区分'],
        settings.distinguishZiShiEnabled ? '开启' : '关闭');
    expect(result.disclaimer, isNotEmpty);
  });

  test('五斗金章受生经执行复用原八字设置、数据与原有口径说明', () async {
    const arguments = {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'method': 'wudou',
    };
    final settings = SettingsRepository.instance;
    final chart = computeBaZiPaipan(
      DateTime(1990, 1, 2, 8, 30),
      useTrueSolarTime: settings.useTrueSolarTime,
      ratHourMode: settings.distinguishZiShiEnabled,
    );
    final expected = ShoushengData.computeWudou(chart.gans[2], chart.zhis[3]);

    final result = await ShoushengDebtToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'shousheng_debt');
    expect(result.validateFor('shousheng_debt'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.arguments, arguments);
    expect(result.sourceIds, const [
      ShoushengDebtToolExecutor.sourceId,
      ShoushengDebtToolExecutor.wudouDataSourceId,
    ]);
    expect(result.values['查询体系'], '五斗金章受生经');
    expect(result.values['五斗本命钱数据'], contains(expected.fiveDou['dou'].toString()));
    expect(result.values['十二库神数据'], contains(expected.kushen['ku_no'].toString()));
    expect(result.values['口径说明'], ShoushengData.wudouNote);
    expect(result.disclaimer, isNotEmpty);
  });

  test('拒绝缺失/非法日期、出生时间、查询体系和未声明参数', () async {
    final missingDate = await ShoushengDebtToolExecutor.execute(const {
      'birth_time': '08:30',
      'method': 'luku',
    });
    expect(missingDate.status, AssistantToolExecutionStatus.failed);
    expect(missingDate.sourceIds, isEmpty);
    expect(missingDate.values['未执行原因'], contains('出生日期'));

    final missingTime = await ShoushengDebtToolExecutor.execute(const {
      'birth_date': '1990-01-02',
      'method': 'luku',
    });
    expect(missingTime.status, AssistantToolExecutionStatus.failed);
    expect(missingTime.sourceIds, isEmpty);
    expect(missingTime.values['未执行原因'], contains('出生时间'));

    final missingMethod = await ShoushengDebtToolExecutor.execute(const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
    });
    expect(missingMethod.status, AssistantToolExecutionStatus.failed);
    expect(missingMethod.sourceIds, isEmpty);
    expect(missingMethod.values['未执行原因'], contains('查询体系'));

    final invalidMethod = await ShoushengDebtToolExecutor.execute(const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'method': 'guess',
    });
    expect(invalidMethod.status, AssistantToolExecutionStatus.failed);
    expect(invalidMethod.sourceIds, isEmpty);

    for (final invalidDate in ['1990-02-30', '1919-12-31', '2999-01-01']) {
      final result = await ShoushengDebtToolExecutor.execute({
        'birth_date': invalidDate,
        'birth_time': '08:30',
        'method': 'luku',
      });
      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.sourceIds, isEmpty);
      expect(result.values['未执行原因'], contains('出生日期'));
    }

    for (final invalidTime in ['24:00', '25:90', '8:30']) {
      final result = await ShoushengDebtToolExecutor.execute({
        'birth_date': '1990-01-02',
        'birth_time': invalidTime,
        'method': 'luku',
      });
      expect(result.status, AssistantToolExecutionStatus.failed);
      expect(result.sourceIds, isEmpty);
      expect(result.values['未执行原因'], contains('出生时间'));
    }

    final unknown = await ShoushengDebtToolExecutor.execute(const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'method': 'luku',
      'birthplace': '上海',
    });
    expect(unknown.status, AssistantToolExecutionStatus.failed);
    expect(unknown.sourceIds, isEmpty);
    expect(unknown.values['未执行原因'], contains('未声明'));
  });
}
