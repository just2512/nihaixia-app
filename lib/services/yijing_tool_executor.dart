import 'dart:math';

import '../data/yijing_data.dart';
import '../engine/yijing_engine.dart';
import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'tool_argument_support.dart';

/// Headless adapter for the four existing YiJingScreen casting methods.
/// All hexagram math remains in YiJingEngine; this class only validates inputs,
/// records app-generated inputs and packages the deterministic result.
class YiJingToolExecutor {
  static const String sourceId = 'local-engine:yijing';
  static const String dataSourceId = 'local-data:yijing-hexagrams';
  static const String resultSchemaVersion = 'yijing-structured-result-v1';
  static const String ruleVersion =
      'yijing-engine@78300a5185134ab4d4a4e4ff30e26d9da49fb6b1;'
      'yijing-data@f36a804903fa6b85235398999a47f2586a7f1573';

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
  }) =>
      ToolArgumentSupport.prepareYiJingArguments(
        arguments,
        now: now,
        rng: rng,
      );

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

    // Number/time/manual modes populate the single main line in
    // CastResult.moving; only coin mode populates movingLines for multiple
    // moving lines. Do not read movingTitles/movingTexts for the former:
    // their getters intentionally describe an empty movingLines list as static.
    final movingTitles = method == 'coins'
        ? cast.movingTitles
        : [cast.movingTitle];
    final movingTexts = method == 'coins'
        ? cast.movingTexts
        : [cast.movingText];
    final movingPositions = method == 'coins'
        ? (cast.movingLines.isEmpty ? '无（静卦）' : cast.movingLines.join('、'))
        : (cast.moving == 0 ? '无（静卦）' : cast.moving.toString());
    final values = <String, String>{
      '起卦方式': cast.method,
      '本卦': '第${cast.primary.seq}卦 ${cast.primary.name}',
      '卦辞': cast.primary.judgement,
      '动爻': movingTitles.join('、'),
      '动爻位置（初爻至上爻）': movingPositions,
      '爻辞': movingTexts.join('；'),
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

  /// Build an immutable full-result snapshot from the exact inputs the app
  /// actually used. This never regenerates timestamps or coin tosses.
  static Map<String, Object?> createStructuredSnapshot(
    Map<String, String> arguments,
  ) {
    final execution = execute(arguments);
    if (execution.status != AssistantToolExecutionStatus.succeeded ||
        execution.toolId != 'yijing' ||
        !execution.sourceIds.contains(sourceId) ||
        !execution.sourceIds.contains(dataSourceId)) {
      throw ArgumentError(
        'A structured YiJing snapshot requires a successful source-bound local execution.',
      );
    }
    final cast = _castFromArguments(arguments);
    if (cast == null) {
      throw ArgumentError('The YiJing inputs cannot be reconstructed exactly.');
    }
    final method = arguments['method']!;
    final base = <String, Object?>{
      'capabilityId': 'yijing',
      'resultSchemaVersion': resultSchemaVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': const [sourceId, dataSourceId],
      'input': <String, Object?>{
        'method': method,
        'arguments': Map<String, String>.unmodifiable(arguments),
        'inputConvention': switch (method) {
          'number' => '用户输入的两个非负整数；原样保留。',
          'time' => 'App 生成并保存的本地 ISO-8601 时间；不重新读取当前时间。',
          'manual' => '用户选定的上卦、下卦先天数及动爻位置。',
          'coins' => 'App 实际生成并保存的六次铜钱值，顺序为初爻至上爻。',
          _ => 'MISSING',
        },
      },
      'result': _serializeCast(cast, method: method),
      'units': const <String, Object?>{
        'hexagram.seq': '通行本《周易》King Wen 卦序，1–64。',
        'trigram.index': 'kTrigrams 中的零基数组索引；xiantian 是先天数 1–8。',
        'primaryLines': '六爻，自下而上；1=阳，0=阴。',
        'moving': '单动爻位置 1–6；0=静卦。铜钱方式以 movingLines 记录全部动爻。',
        'movingLines': '全部动爻位置，按初爻至上爻升序。',
      },
      'missingFields': const <String>[],
      'displaySummary': <String, Object?>{
        'title': execution.title,
        'values': execution.values,
        'disclaimer': execution.disclaimer,
      },
      'ruleVersion': ruleVersion,
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: base);
    return Map<String, Object?>.unmodifiable({
      ...base,
      'snapshotId': snapshotId,
    });
  }

  static bool matchesCast({
    required Map<String, Object?> snapshot,
    required CastResult cast,
  }) {
    final input = snapshot['input'];
    if (input is! Map || input['method'] is! String) return false;
    try {
      return AiToolResultSnapshot.canonicalJson(snapshot['result']) ==
          AiToolResultSnapshot.canonicalJson(
            _serializeCast(cast, method: input['method'] as String),
          );
    } catch (_) {
      return false;
    }
  }

  static CastResult? _castFromArguments(Map<String, String> arguments) {
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
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) return null;
    switch (arguments['method']) {
      case 'number':
        if (const ['at', 'coins', 'upper', 'lower', 'moving']
            .any(arguments.containsKey)) {
          return null;
        }
        final first = int.tryParse(arguments['first'] ?? '');
        final second = int.tryParse(arguments['second'] ?? '');
        if (first == null || second == null || first < 0 || second < 0) {
          return null;
        }
        return YiJingEngine.castByNumbers(first, second);
      case 'time':
        if (const ['first', 'second', 'upper', 'lower', 'moving', 'coins']
            .any(arguments.containsKey)) {
          return null;
        }
        final rawAt = arguments['at'];
        final at = rawAt == null ? null : DateTime.tryParse(rawAt);
        if (at == null || at.toIso8601String() != rawAt) return null;
        return YiJingEngine.castByTime(at);
      case 'manual':
        if (const ['first', 'second', 'at', 'coins']
            .any(arguments.containsKey)) {
          return null;
        }
        final upper = int.tryParse(arguments['upper'] ?? '');
        final lower = int.tryParse(arguments['lower'] ?? '');
        final moving = int.tryParse(arguments['moving'] ?? '');
        if (upper == null ||
            lower == null ||
            moving == null ||
            upper < 1 ||
            upper > 8 ||
            lower < 1 ||
            lower > 8 ||
            moving < 0 ||
            moving > 6) {
          return null;
        }
        return YiJingEngine.castManual(upper, lower, moving);
      case 'coins':
        if (const ['first', 'second', 'upper', 'lower', 'moving', 'at']
            .any(arguments.containsKey)) {
          return null;
        }
        final rolls = arguments['coins']
            ?.split(',')
            .map(int.tryParse)
            .toList(growable: false);
        if (rolls == null ||
            rolls.length != 6 ||
            rolls.any(
              (value) => value == null || !const {6, 7, 8, 9}.contains(value),
            )) {
          return null;
        }
        return YiJingEngine.castByCoins(
          rolls.cast<int>().toList(growable: false),
        );
      default:
        return null;
    }
  }

  static Map<String, Object?> _serializeHexagram(Hexagram hexagram) {
    final upper = kTrigrams[hexagram.upper];
    final lower = kTrigrams[hexagram.lower];
    return <String, Object?>{
      'seq': hexagram.seq,
      'name': hexagram.name,
      'symbol': YiJingEngine.symbol(hexagram.seq),
      'upper': <String, Object?>{
        'index': hexagram.upper,
        'xiantian': upper.xiantian,
        'name': upper.name,
        'nature': upper.nature,
        'symbol': upper.symbol,
        'lines': List<int>.unmodifiable(upper.lines),
      },
      'lower': <String, Object?>{
        'index': hexagram.lower,
        'xiantian': lower.xiantian,
        'name': lower.name,
        'nature': lower.nature,
        'symbol': lower.symbol,
        'lines': List<int>.unmodifiable(lower.lines),
      },
      'judgement': hexagram.judgement,
      'lines': List<String>.unmodifiable(hexagram.lines),
      'renjian': hexagram.renjian,
    };
  }

  static Map<String, Object?> _serializeCast(
    CastResult cast, {
    required String method,
  }) {
    // The legacy engine keeps movingLines empty for number/time/manual
    // methods even when its primary moving field is non-zero. The legacy
    // executor handles that distinction explicitly; the structured snapshot
    // must preserve the same visible result rather than treating it as static.
    final movingTitles =
        method == 'coins' ? cast.movingTitles : [cast.movingTitle];
    final movingTexts =
        method == 'coins' ? cast.movingTexts : [cast.movingText];
    return <String, Object?>{
      'method': method,
      'methodDescription': cast.method,
      'primary': _serializeHexagram(cast.primary),
      'primaryLines': List<int>.unmodifiable(cast.primaryLines),
      'moving': cast.moving,
      'movingLines': List<int>.unmodifiable(cast.movingLines),
      'movingTitles': List<String>.unmodifiable(movingTitles),
      'movingTexts': List<String>.unmodifiable(movingTexts),
      'changed': cast.changed == null
          ? null
          : _serializeHexagram(cast.changed!),
      'nuclear': cast.nuclear == null
          ? null
          : _serializeHexagram(cast.nuclear!),
    };
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
