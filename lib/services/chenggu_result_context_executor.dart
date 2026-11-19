import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'chenggu_tool_executor.dart';

class ChengguResultContextExecution {
  const ChengguResultContextExecution({required this.result, this.structuredSnapshot});
  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;
  bool get succeeded => result.status == AssistantToolExecutionStatus.succeeded && structuredSnapshot != null;
}

/// Captures the existing Chenggu engine output; exact birth details remain local-only.
class ChengguResultContextExecutor {
  static const moduleId = 'chenggu';
  static const resultSchemaVersion = 'chenggu-structured-result-v1';
  static const ruleVersion = '$version';

  static Future<ChengguResultContextExecution> executeWithSnapshot(Map<String, String> arguments) async {
    const allowed = {'birth_date', 'birth_time'};
    if (arguments.length != 2 || arguments.keys.any((key) => !allowed.contains(key))) {
      return _failure(arguments, '只接受 birth_date 与 birth_time 两个明确输入字段。');
    }
    final result = await ChengguToolExecutor.execute(arguments);
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(arguments).isNotEmpty ||
        result.sourceIds.length != 2 ||
        !result.sourceIds.contains(ChengguToolExecutor.sourceId) ||
        !result.sourceIds.contains(ChengguToolExecutor.dataSourceId) ||
        result.arguments.length != 2 ||
        result.values['总骨重']?.isNotEmpty != true ||
        result.values['称骨歌诀']?.isNotEmpty != true) {
      return ChengguResultContextExecution(result: result);
    }
    final values = <String, Object?>{for (final entry in result.values.entries) entry.key: entry.value};
    final missingFields = values.entries.where((e) => e.value == 'MISSING' || (e.value is String && (e.value as String).isEmpty)).map((e) => e.key).toList(growable: false);
    final base = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': const [ChengguToolExecutor.sourceId, ChengguToolExecutor.dataSourceId],
      'input': <String, Object?>{
        'method': 'explicitBirthDateTime',
        'arguments': Map<String, String>.unmodifiable(result.arguments),
        'settings': <String, Object?>{
          'useTrueSolarTime': result.values['真太阳时校正'] == '开启',
          'distinguishZiShi': result.values['早晚子时区分'] == '开启',
        },
        'calculationBasis': 'Bazi engine settings; lunar month/day at local noon; ChengguData local asset',
      },
      'result': <String, Object?>{'values': values, 'disclaimer': result.disclaimer ?? '传统民俗文化参考，非科学预测。'},
      'units': const <String, Object?>{'result.values.总骨重': '两/钱；括号内为总钱数', 'result.values.出生时辰': '地支时辰', 'result.values.称骨计算时柱地支': '地支'},
      'missingFields': missingFields,
      'displaySummary': '${values['总骨重'] ?? 'MISSING'} · ${values['出生农历口径'] ?? 'MISSING'}',
      'privacy': const <String, Object?>{'exactBirthDateAndTime': 'LOCAL_VERIFICATION_ONLY', 'modelPromptPolicy': 'REDACT_EXACT_BIRTH_DATE_AND_TIME'},
    };
    final snapshotId = AiToolResultSnapshot.createStructuredId(snapshot: base);
    return ChengguResultContextExecution(result: result, structuredSnapshot: _deepUnmodifiable({...base, 'snapshotId': snapshotId}) as Map<String, Object?>);
  }

  static ChengguResultContextExecution _failure(Map<String, String> arguments, String message) => ChengguResultContextExecution(
    result: AssistantToolResult(toolId: moduleId, title: '袁天罡称骨', status: AssistantToolExecutionStatus.failed, values: {'未执行原因': message}, arguments: Map<String, String>.unmodifiable(arguments), disclaimer: '上下文参数未通过校验；本次没有生成可供 AI 使用的结果快照。'),
  );

  static Object? _deepUnmodifiable(Object? value) {
    if (value is Map) return Map<String, Object?>.unmodifiable({for (final entry in value.entries) entry.key as String: _deepUnmodifiable(entry.value)});
    if (value is List) return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
    return value;
  }
}
