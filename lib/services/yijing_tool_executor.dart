import 'dart:math';

import '../data/yijing_data.dart';
import '../engine/yijing_engine.dart';
import '../models/assistant_tool_result.dart';

/// Headless adapter for the four deterministic methods already implemented
/// by YiJingScreen. The hexagram engine and its interpretation data remain
/// the single source of calculation truth.
class YiJingToolExecutor {
  static const String sourceId = 'local-engine:yijing-engine';
  static const String dataSourceId = 'local-data:yijing-hexagrams';

  static const Map<String, String> methodLabels = {
    'numbers': '数字起卦',
    'time': '时间起卦（App 本地当前时间）',
    'manual': '手动选卦',
    'coins': '六爻铜钱摇卦',
  };

  static const Map<String, int> trigramNumbers = {
    '乾': 1,
    '兑': 2,
    '离': 3,
    '震': 4,
    '巽': 5,
    '坎': 6,
    '艮': 7,
    '坤': 8,
  };

  /// Reuse the page's actual three-coin semantics for each of six lines.
  /// Values are saved as 6/7/8/9 in assistant metadata so the result can be
  /// replayed exactly; the model never invents coin outcomes.
  static List<int> generateCoinValues({Random? random}) {
    final rng = random ?? Random();
    return List<int>.generate(6, (_) {
      final heads = List<bool>.generate(3, (_) => rng.nextBool())
          .where((isHead) => isHead)
          .length;
      return switch (heads) {
        3 => 9,
        2 => 7,
        1 => 8,
        _ => 6,
      };
    }, growable: false);
  }

  static AssistantToolResult execute(Map<String, String> arguments) {
    const allowedKeys = {
      'method',
      'number_a',
      'number_b',
      'upper',
      'lower',
      'moving',
      'coins',
      'cast_at',
    };
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      return _failure(arguments, '包含未声明的易经起卦参数；本次未执行。');
    }

    final method = arguments['method'];
    if (!methodLabels.containsKey(method)) {
      return _failure(
        arguments,
        '缺少或不支持起卦方式；请选择数字、时间、手动或铜钱起卦。',
      );
    }

    late final CastResult cast;
    final normalized = <String, String>{'method': method!};

    switch (method) {
      case 'numbers':
        if (_hasAny(arguments, const {'upper', 'lower', 'moving', 'coins', 'cast_at'})) {
          return _failure(arguments, '数字起卦不接受手动、铜钱或时间参数；本次未执行。');
        }
        final a = int.tryParse(arguments['number_a'] ?? '');
        final b = int.tryParse(arguments['number_b'] ?? '');
        if (a == null || b == null) {
          return _failure(arguments, '数字起卦需要两个明确的整数；本次未执行。');
        }
        if (a < 0 || b < 0 || a > 0x7fffffff || b > 0x7fffffff) {
          return _failure(arguments, '两个数字必须是 0 至 2147483647 的非负整数；本次未执行。');
        }
        cast = YiJingEngine.castByNumbers(a, b);
        normalized
          ..['number_a'] = '$a'
          ..['number_b'] = '$b';
        break;

      case 'time':
        if (_hasAny(arguments, const {'number_a', 'number_b', 'upper', 'lower', 'moving', 'coins'})) {
          return _failure(arguments, '时间起卦不接受其他模式的参数；本次未执行。');
        }
        final rawTime = arguments['cast_at'];
        final castAt = rawTime == null ? null : DateTime.tryParse(rawTime);
        if (castAt == null) {
          return _failure(
            arguments,
            '缺少 App 已记录的本地起卦时间；本次未读取默认时间，也未执行。',
          );
        }
        cast = YiJingEngine.castByTime(castAt);
        normalized['cast_at'] = castAt.toIso8601String();
        break;

      case 'manual':
        if (_hasAny(arguments, const {'number_a', 'number_b', 'coins', 'cast_at'})) {
          return _failure(arguments, '手动选卦不接受数字起卦、铜钱或时间参数；本次未执行。');
        }
        final upper = int.tryParse(arguments['upper'] ?? '');
        final lower = int.tryParse(arguments['lower'] ?? '');
        final moving = int.tryParse(arguments['moving'] ?? '');
        if (upper == null || lower == null || moving == null) {
          return _failure(arguments, '手动选卦需要明确的上卦、下卦和动爻（0 表示静卦）；本次未执行。');
        }
        if (upper < 1 || upper > 8 || lower < 1 || lower > 8 ||
            moving < 0 || moving > 6) {
          return _failure(arguments, '上卦和下卦先天数必须为 1–8，动爻必须为 0–6；本次未执行。');
        }
        cast = YiJingEngine.castManual(upper, lower, moving);
        normalized
          ..['upper'] = '$upper'
          ..['lower'] = '$lower'
          ..['moving'] = '$moving';
        break;

      case 'coins':
        if (_hasAny(arguments, const {'number_a', 'number_b', 'upper', 'lower', 'moving', 'cast_at'})) {
          return _failure(arguments, '铜钱摇卦不接受其他模式的参数；本次未执行。');
        }
        final values = (arguments['coins'] ?? '')
            .split(',')
            .map((part) => int.tryParse(part.trim()))
            .toList(growable: false);
        if (values.length != 6 ||
            values.any((value) => value == null || !const {6, 7, 8, 9}.contains(value))) {
          return _failure(arguments, '铜钱起卦必须由 App 生成并记录六次真实投掷结果，每爻只能为 6/7/8/9；本次未执行。');
        }
        final coinValues = values.cast<int>();
        cast = YiJingEngine.castByCoins(coinValues);
        normalized['coins'] = coinValues.join(',');
        break;
    }

    final primary = cast.primary;
    final primaryLines = cast.primaryLines;
    final movingDetails = <String>[
      for (var i = 0; i < cast.movingLines.length; i++)
        '${cast.movingTitles[i]}：${cast.movingTexts[i]}',
    ];
    final changed = cast.changed;
    final nuclear = cast.nuclear;
    final values = <String, String>{
      '起卦方式': methodLabels[method]!,
      '起卦参数': switch (method) {
        'numbers' => '第一数 ${normalized['number_a']}；第二数 ${normalized['number_b']}',
        'time' => 'App 本地时间 ${normalized['cast_at']}',
        'manual' => '上卦先天数 ${normalized['upper']}；下卦先天数 ${normalized['lower']}；动爻 ${normalized['moving']}',
        'coins' => '初爻至上爻：${normalized['coins']}',
        _ => 'MISSING',
      },
      '本卦': '第${primary.seq}卦 ${primary.name} ${YiJingEngine.symbol(primary.seq)}',
      '本卦卦辞': primary.judgement,
      '本卦六爻（初爻至上爻）':
          primaryLines.map((line) => line == 1 ? '阳' : '阴').join('、'),
      '动爻': cast.movingLines.isEmpty ? '静卦（六爻皆静）' : cast.movingTitles.join('、'),
      '动爻爻辞': cast.movingLines.isEmpty ? primary.judgement : movingDetails.join('；'),
      if (changed != null)
        '变卦': '第${changed.seq}卦 ${changed.name} ${YiJingEngine.symbol(changed.seq)}',
      if (changed != null) '变卦卦辞': changed.judgement,
      if (nuclear != null)
        '互卦': '第${nuclear.seq}卦 ${nuclear.name} ${YiJingEngine.symbol(nuclear.seq)}',
      if (nuclear != null) '互卦卦辞': nuclear.judgement,
      '引擎方法记录': cast.method,
    };

    return AssistantToolResult(
      toolId: 'yijing',
      title: '易经起卦结果',
      values: values,
      arguments: Map<String, String>.unmodifiable(normalized),
      sourceIds: const [sourceId, dataSourceId],
      disclaimer:
          '结果由 App 本地 YiJingEngine 确定性计算，AI 只负责归纳解释。卦辞、爻辞来自 App 内置易经数据；仅供传统文化学习参考，不是科学预测或确定性结论，不用于医疗、法律、投资或其他重要决策。',
    );
  }

  static bool _hasAny(Map<String, String> values, Set<String> keys) =>
      keys.any(values.containsKey);

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'yijing',
        title: '易经起卦结果',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行易经起卦。',
      );
}
