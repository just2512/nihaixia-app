import 'dart:math';

import '../engine/yijing_engine.dart';
import '../models/assistant_tool_result.dart';

/// Headless adapter for the four existing YiJingScreen casting methods.
/// All hexagram math remains in YiJingEngine; this class only validates inputs,
/// records app-generated inputs and packages the deterministic result.
class YiJingToolExecutor {
  static const String sourceId = 'local-engine:yijing';
  static const String dataSourceId = 'local-data:yijing-hexagrams';

  static const Map<String, int> trigramNumbers = {
    '乾': 1,
    '兑': 2,
    '離': 3,
    '离': 3,
    '震': 4,
    '巽': 5,
    '坎': 6,
    '艮': 7,
    '坤': 8,
  };

  /// App-owned values for modes that use device state or randomness.
  /// Every new execution overwrites caller-supplied values. The generated
  /// timestamp or six coin tosses are persisted with the result; history
  /// displays/replays those stored arguments without generating them again.
  static Map<String, String> prepareExecutionArguments(
    Map<String, String> arguments, {
    DateTime? now,
    Random? rng,
  }) {
    final prepared = <String, String>{...arguments};
    final method = prepared['method'];
    if (method == 'time') {
      prepared['at'] = (now ?? DateTime.now()).toIso8601String();
    } else if (method == 'coins') {
      final random = rng ?? Random();
      final rolls = <String>[];
      for (var line = 0; line < 6; line++) {
        final heads = List<bool>.generate(3, (_) => random.nextBool())
            .where((isHead) => isHead)
            .length;
        rolls.add(switch (heads) {
          3 => '9',
          2 => '7',
          1 => '8',
          _ => '6',
        });
      }
      prepared['coins'] = rolls.join(',');
    }
    return Map<String, String>.unmodifiable(prepared);
  }

  static AssistantToolResult execute(Map<String, String> arguments) {
    const allowedKeys = {
      'method',
      'first',
      'second',
      'upper',
      'lower',
      'moving',
      'at',
      'coins',
    };
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      return _failure(arguments, '包含未声明的易经起卦参数，未执行计算。');
    }

    final method = arguments['method'];
    if (!const {'number', 'time', 'manual', 'coins'}.contains(method)) {
      return _failure(arguments, '缺少或不支持起卦方式；请选择数字、当前时间、手动选卦或铜钱摇卦。');
    }

    late final CastResult cast;
    switch (method) {
      case 'number':
        if (const ['at', 'coins', 'upper', 'lower', 'moving']
            .any(arguments.containsKey)) {
          return _failure(arguments, '数字起卦包含其他方式的参数，未执行计算。');
        }
        final first = int.tryParse(arguments['first'] ?? '');
        final second = int.tryParse(arguments['second'] ?? '');
        if (first == null || second == null || first < 0 || second < 0) {
          return _failure(arguments, '数字起卦需要两个非负整数；未执行计算。');
        }
        cast = YiJingEngine.castByNumbers(first, second);
        break;

      case 'time':
        if (const ['first', 'second', 'upper', 'lower', 'moving', 'coins']
            .any(arguments.containsKey)) {
          return _failure(arguments, '当前时间起卦包含其他方式的参数，未执行计算。');
        }
        final rawAt = arguments['at'];
        final at = rawAt == null ? null : DateTime.tryParse(rawAt);
        if (at == null || at.toIso8601String() != rawAt) {
          return _failure(arguments, '当前时间起卦缺少 App 记录的有效本地时间，未执行计算。');
        }
        cast = YiJingEngine.castByTime(at);
        break;

      case 'manual':
        if (const ['first', 'second', 'at', 'coins']
            .any(arguments.containsKey)) {
          return _failure(arguments, '手动选卦包含其他方式的参数，未执行计算。');
        }
        final upper = int.tryParse(arguments['upper'] ?? '');
        final lower = int.tryParse(arguments['lower'] ?? '');
        final moving = int.tryParse(arguments['moving'] ?? '');
        if (upper == null || lower == null || moving == null ||
            upper < 1 || upper > 8 ||
            lower < 1 || lower > 8 ||
            moving < 0 || moving > 6) {
          return _failure(arguments, '手动选卦需要上卦、下卦（1–8）和动爻（0–6）；未执行计算。');
        }
        cast = YiJingEngine.castManual(upper, lower, moving);
        break;

      case 'coins':
        if (const ['first', 'second', 'upper', 'lower', 'moving', 'at']
            .any(arguments.containsKey)) {
          return _failure(arguments, '铜钱摇卦包含其他方式的参数，未执行计算。');
        }
        final raw = arguments['coins'];
        final rolls = raw?.split(',').map(int.tryParse).toList(growable: false);
        if (rolls == null || rolls.length != 6 ||
            rolls.any((value) => value == null || !const {6, 7, 8, 9}.contains(value))) {
          return _failure(arguments, '铜钱摇卦必须保存 App 实际生成的六次投掷值（每爻为 6/7/8/9）；未执行计算。');
        }
        cast = YiJingEngine.castByCoins(rolls.cast<int>().toList(growable: false));
        break;
    }

    final values = <String, String>{
      '起卦方式': cast.method,
      '本卦': '第${cast.primary.seq}卦 ${cast.primary.name}',
      '卦辞': cast.primary.judgement,
      '动爻': cast.movingTitles.join('、'),
      '爻辞': cast.movingTexts.join('；'),
      if (cast.nuclear != null)
        '互卦': '第${cast.nuclear!.seq}卦 ${cast.nuclear!.name}',
      if (cast.nuclear != null) '互卦卦辞': cast.nuclear!.judgement,
      if (cast.changed != null)
        '变卦': '第${cast.changed!.seq}卦 ${cast.changed!.name}',
      if (cast.changed != null) '变卦卦辞': cast.changed!.judgement,
      '本卦人事应用资料': cast.primary.renjian,
      if (method == 'time') '实际起卦时刻': arguments['at']!,
      if (method == 'coins')
        '六次铜钱投掷值（初爻至上爻）': arguments['coins']!,
    };

    return AssistantToolResult(
      toolId: 'yijing',
      title: '易经起卦结果',
      values: Map<String, String>.unmodifiable(values),
      sourceIds: const [sourceId, dataSourceId],
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '结果由 App 原有 YiJingEngine 和本地六十四卦资料生成，仅供传统文化学习参考，不是科学预测或确定性结论，不用于医疗、法律、投资等重要决策。',
    );
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'yijing',
        title: '易经起卦',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行起卦。',
      );
}
