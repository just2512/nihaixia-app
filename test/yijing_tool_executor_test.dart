import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/yijing_engine.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/yijing_tool_executor.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 14, 13, 26);

  test('数字起卦复用原引擎并保留两个原始整数参数', () {
    const arguments = {'method': 'number', 'first': '3', 'second': '7'};
    final cast = YiJingEngine.castByNumbers(3, 7);
    final result = YiJingToolExecutor.execute(arguments);

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('yijing'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.sourceIds, const [
      YiJingToolExecutor.sourceId,
      YiJingToolExecutor.dataSourceId,
    ]);
    expect(result.arguments, arguments);
    expect(result.values['本卦'], '第${cast.primary.seq}卦 ${cast.primary.name}');
    expect(result.values['卦辞'], cast.primary.judgement);
    expect(result.values['动爻'], cast.movingTitles.join('、'));
    expect(result.values['爻辞'], cast.movingTexts.join('；'));
  });

  test('当前时间由 App 注入并记录，可用完全相同的本地时间回放', () {
    final prepared = YiJingToolExecutor.prepareExecutionArguments(
      const {'method': 'time'},
      now: fixedNow,
    );
    expect(prepared, const {
      'method': 'time',
      'at': '2026-11-14T13:26:00.000',
    });
    final cast = YiJingEngine.castByTime(fixedNow);
    final result = YiJingToolExecutor.execute(prepared);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateArgumentsMatch(prepared), isEmpty);
    expect(result.values['实际起卦时刻'], prepared['at']);
    expect(result.values['本卦'], '第${cast.primary.seq}卦 ${cast.primary.name}');
  });

  test('手动选卦校验上卦、下卦和动爻后调用原引擎', () {
    const arguments = {
      'method': 'manual',
      'upper': '1',
      'lower': '8',
      'moving': '0',
    };
    final cast = YiJingEngine.castManual(1, 8, 0);
    final result = YiJingToolExecutor.execute(arguments);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.values['本卦'], '第${cast.primary.seq}卦 ${cast.primary.name}');
    expect(result.values['动爻'], '静卦（六爻皆静）');
    expect(result.values['变卦'], isNull);
  });

  test('六次铜钱投掷由 App 随机生成、持久化后可确定性回放', () {
    final prepared = YiJingToolExecutor.prepareExecutionArguments(
      const {'method': 'coins'},
      rng: Random(41),
    );
    final values = prepared['coins']!.split(',').map(int.parse).toList();
    expect(values, hasLength(6));
    expect(values.every(const {6, 7, 8, 9}.contains), isTrue);

    final cast = YiJingEngine.castByCoins(values);
    final result = YiJingToolExecutor.execute(prepared);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateArgumentsMatch(prepared), isEmpty);
    expect(result.values['六次铜钱投掷值（初爻至上爻）'], prepared['coins']);
    expect(result.values['本卦'], '第${cast.primary.seq}卦 ${cast.primary.name}');
    expect(result.values['动爻'], cast.movingTitles.join('、'));
  });

  test('缺少方法专属参数、无效参数或混合模式均 fail closed', () {
    for (final arguments in [
      const {'method': 'number', 'first': '3'},
      const {'method': 'manual', 'upper': '1', 'lower': '8'},
      const {'method': 'time'},
      const {'method': 'coins', 'coins': '6,7,8'},
      const {'method': 'number', 'first': '3', 'second': '7', 'at': '2026-11-14T13:26:00.000'},
      const {'method': 'manual', 'upper': '9', 'lower': '8', 'moving': '0'},
    ]) {
      final result = YiJingToolExecutor.execute(arguments);
      expect(result.status, AssistantToolExecutionStatus.failed,
          reason: arguments.toString());
      expect(result.sourceIds, isEmpty);
    }
  });

  test('未知输入字段不进入业务计算', () {
    final result = YiJingToolExecutor.execute(const {
      'method': 'number',
      'first': '3',
      'second': '7',
      'model_guess': 'fake',
    });
    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.sourceIds, isEmpty);
  });
}
