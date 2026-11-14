import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/saved_chart_repository.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/saved_chart_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int savedId;

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.configureTestDatabase(
      'saved_chart_tool_executor_test.db',
      factory: databaseFactoryFfi,
    );
  });

  setUp(() async {
    DatabaseHelper.resetForTest();
    final existing = await SavedChartRepository.getAll();
    for (final chart in existing) {
      if (chart.id != null) await SavedChartRepository.delete(chart.id!);
    }
    savedId = await SavedChartRepository.insert(
      SavedChart(
        name: '测试命盘 1990-01-02 男',
        isMale: true,
        solarIso: DateTime(1990, 1, 2, 8, 30).toIso8601String(),
        lng: 121.47,
        lat: 31.23,
        cityName: '上海市',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });

  tearDown(() async {
    await SavedChartRepository.delete(savedId);
  });

  tearDownAll(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  test('八字重算复用 App 原引擎，返回所选记录、当前口径及来源', () async {
    final arguments = {
      'saved_chart_id': savedId.toString(),
      'chart_type': 'bazi',
    };
    final result = await SavedChartToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'saved_charts');
    expect(result.validateFor('saved_charts'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.values['保存记录 ID'], savedId.toString());
    expect(result.values['保存记录名称'], '测试命盘 1990-01-02 男');
    expect(result.values['排盘类型'], '八字');
    expect(result.values['完整排盘结果'], contains('四柱：'));
    expect(result.values['完整排盘结果'], contains('1990-01-02 08:30'));
    expect(result.values['本次计算设置'], contains('真太阳时：'));
    expect(result.sourceIds, [
      '${SavedChartToolExecutor.savedChartSourcePrefix}$savedId',
      SavedChartToolExecutor.baziSourceId,
    ]);
    expect(result.disclaimer, contains('不是历史结果快照'));
    expect(result.disclaimer, contains('AI 只负责解释'));
  });

  test('紫微重算复用 App 原引擎并保留用户所选记录来源', () async {
    final arguments = {
      'saved_chart_id': savedId.toString(),
      'chart_type': 'ziwei',
    };
    final result = await SavedChartToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'saved_charts');
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.values['排盘类型'], '紫微斗数');
    expect(result.values['完整排盘结果'], contains('十二宫星曜'));
    expect(result.sourceIds, [
      '${SavedChartToolExecutor.savedChartSourcePrefix}$savedId',
      SavedChartToolExecutor.ziweiSourceId,
    ]);
  });

  test('拒绝缺失参数、无效记录 ID、无效类型和未声明字段', () async {
    final missing = await SavedChartToolExecutor.execute(const {});
    expect(missing.status, AssistantToolExecutionStatus.failed);
    expect(missing.sourceIds, isEmpty);

    final missingType = await SavedChartToolExecutor.execute({
      'saved_chart_id': savedId.toString(),
    });
    expect(missingType.status, AssistantToolExecutionStatus.failed);
    expect(missingType.values['未执行原因'], contains('明确选择八字或紫微'));

    final unknownRecord = await SavedChartToolExecutor.execute({
      'saved_chart_id': '999999',
      'chart_type': 'bazi',
    });
    expect(unknownRecord.status, AssistantToolExecutionStatus.failed);
    expect(unknownRecord.values['未执行原因'], contains('不存在'));

    final undeclared = await SavedChartToolExecutor.execute({
      'saved_chart_id': savedId.toString(),
      'chart_type': 'bazi',
      'rawPrompt': '模型不能注入原始指令',
    });
    expect(undeclared.status, AssistantToolExecutionStatus.failed);
    expect(undeclared.values['未执行原因'], contains('未声明'));
    expect(undeclared.sourceIds, isEmpty);
  });

  test('缺少保存地点时显式标记原引擎默认地点，不伪装为真实出生地', () async {
    final noLocationId = await SavedChartRepository.insert(
      SavedChart(
        name: '地点缺失记录',
        isMale: false,
        solarIso: DateTime(1988, 6, 7, 12, 0).toIso8601String(),
        createdAt: DateTime.now().millisecondsSinceEpoch + 1,
      ),
    );
    try {
      final result = await SavedChartToolExecutor.execute({
        'saved_chart_id': noLocationId.toString(),
        'chart_type': 'bazi',
      });
      expect(result.status, AssistantToolExecutionStatus.succeeded);
      expect(result.values['出生地点'], contains('未存地点坐标'));
      expect(result.values['出生地点'], contains('默认东经120°、北纬30°'));
      expect(result.disclaimer, contains('默认地点口径'));
    } finally {
      await SavedChartRepository.delete(noLocationId);
    }
  });

  test('选择器只接受明确记录、名称或最新请求；不因只有一条记录而隐式选择', () {
    final chart = SavedChart(
      id: savedId,
      name: '测试命盘 1990-01-02 男',
      isMale: true,
      solarIso: DateTime(1990, 1, 2, 8, 30).toIso8601String(),
      createdAt: 1,
    );
    final charts = [chart];

    expect(
      SavedChartToolExecutor.resolveRecordId('查看命盘库', charts),
      isNull,
    );
    expect(
      SavedChartToolExecutor.resolveRecordId('ID $savedId', charts),
      savedId,
    );
    expect(
      SavedChartToolExecutor.resolveRecordId(chart.name, charts),
      savedId,
    );
    expect(
      SavedChartToolExecutor.resolveRecordId('查看最近保存的命盘', charts),
      savedId,
    );
    expect(
      SavedChartToolExecutor.resolveRecordId(
        '八字',
        charts,
        pendingArguments: {'saved_chart_id': savedId.toString()},
      ),
      savedId,
    );
    expect(
      SavedChartToolExecutor.resolveRecordId(
        'ID 999999',
        charts,
        pendingArguments: {'saved_chart_id': savedId.toString()},
      ),
      isNull,
      reason: '本轮明确无效 ID 不得静默回退到先前选择',
    );
  });

  test('排盘类型必须来自明确表述或上一轮已确认的选择', () {
    expect(
      SavedChartToolExecutor.resolveChartType('请用八字重排'),
      'bazi',
    );
    expect(
      SavedChartToolExecutor.resolveChartType('请用紫微斗数重排'),
      'ziwei',
    );
    expect(
      SavedChartToolExecutor.resolveChartType('看看这个命盘'),
      isNull,
    );
    expect(
      SavedChartToolExecutor.resolveChartType(
        '看看这个命盘',
        pendingChartType: 'bazi',
      ),
      'bazi',
    );
    expect(
      SavedChartToolExecutor.resolveChartType('八字和紫微都看看'),
      isNull,
    );
  });
}
