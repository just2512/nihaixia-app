import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'headless_tool_dispatcher.dart';
import 'huangdi_siji_tool_service.dart';

class HuangdiSijiResultContextExecution {
  const HuangdiSijiResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Binds the existing deterministic Huangdi Siji lookup to a stable local
/// result snapshot. Birth date/time stay in the local snapshot for replay
/// verification and are redacted before the model prompt is built.
class HuangdiSijiResultContextExecutor {
  static const moduleId = 'huangdi_siji';
  static const resultSchemaVersion = 'huangdi-siji-structured-result-v1';
  static const ruleVersion =
      'tool-executor-blob@40fd13c2758d389b78fecc025359cf61e0e86ce9;'
      'data-access-blob@24fd79105998b897d005285a3bd907e62bd4f299;'
      'data-asset-blob@fc49d1cd4447e3a40b55a0502531c2b745c3902d;'
      'sxwnl_spa_dart@0.18.5';

  static Future<HuangdiSijiResultContextExecution> executeWithSnapshot(
    Map<String, String> arguments,
  ) async {
    const allowed = {'birth_date', 'birth_time'};
    if (arguments.length != 2 ||
        arguments.keys.any((key) => !allowed.contains(key))) {
      return _failure(arguments, '只接受 birth_date 与 birth_time 两个明确输入字段。');
    }

    final result = await HeadlessToolDispatcher.execute(toolId: 'huangdi_siji', arguments: arguments);
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(arguments).isNotEmpty ||
        result.sourceIds.length != 2 ||
        !result.sourceIds.contains(HuangdiSijiToolService.sourceId) ||
        !result.sourceIds.contains(HuangdiSijiToolService.dataSourceId) ||
        result.arguments.length != 2 ||
        result.arguments['birth_date'] is! String ||
        result.arguments['birth_time'] is! String ||
        result.values['对应部位']?.isNotEmpty != true ||
        result.values['部位诗']?.isNotEmpty != true) {
      return HuangdiSijiResultContextExecution(result: result);
    }

    final normalizedArguments = Map<String, String>.unmodifiable(
      result.arguments,
    );
    final values = <String, Object?>{
      for (final entry in result.values.entries) entry.key: entry.value,
    };
    final missingFields = values.entries
        .where((entry) =>
            entry.value == 'MISSING' ||
            (entry.value is String && (entry.value as String).isEmpty))
        .map((entry) => entry.key)
        .toList(growable: false);
    final baseSnapshot = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': const [
        HuangdiSijiToolService.sourceId,
        HuangdiSijiToolService.dataSourceId,
      ],
      'input': <String, Object?>{
        'method': 'explicitBirthDateTime',
        'arguments': normalizedArguments,
        'calculationRules': const <String, Object?>{
          'lunarMonthSource': 'sxwnl_spa_dart',
          'lunarMonthCalculationTime': 'local date at 12:00',
          'earthlyBranchFormula': '((hour.clamp(0, 23) + 1) ~/ 2) % 12',
          'seasonBasis': 'lunar month: 1-3 spring, 4-6 summer, 7-9 autumn, 10-12 winter',
        },
      },
      'result': <String, Object?>{
        'values': values,
        'disclaimer': result.disclaimer ?? '传统民俗文化参考，非科学预测。',
      },
      'units': const <String, Object?>{
        'result.values.农历月份': '农历月份（1-12）',
        'result.values.出生时辰': '地支时辰',
        'result.values.对应部位': '传统民俗文本部位分类',
        'result.values.部位诗': '原始诗文',
      },
      'missingFields': missingFields,
      'displaySummary':
          '${values['季节口径'] ?? 'MISSING'} · ${values['出生时辰'] ?? 'MISSING'} · ${values['对应部位'] ?? 'MISSING'}',
      'privacy': <String, Object?>{
        'exactBirthDateAndTime': 'LOCAL_VERIFICATION_ONLY',
        'modelPromptPolicy': 'REDACT_EXACT_BIRTH_DATE_AND_TIME',
      },
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;

    return HuangdiSijiResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static HuangdiSijiResultContextExecution _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      HuangdiSijiResultContextExecution(
        result: AssistantToolResult(
          toolId: moduleId,
          title: '轩辕黄帝四季歌',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': message},
          arguments: Map<String, String>.unmodifiable(arguments),
          disclaimer: '上下文参数未通过校验；本次没有生成可供 AI 使用的结果快照。',
        ),
      );

  static Object? _deepUnmodifiable(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _deepUnmodifiable(entry.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
    }
    return value;
  }
}
