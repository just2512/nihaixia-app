import '../models/assistant_tool_result.dart';
import '../models/tool_execution_plan.dart';
import '../licensing/feature_authorizer.dart';
import 'ai_tool_result_snapshot.dart';
import 'headless_tool_dispatcher.dart';
import 'solar_term_tool_service.dart';

class SolarTermResultContextExecution {
  const SolarTermResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Captures the existing local solar-term knowledge query as an immutable,
/// source-bound explanation context. It never rewrites or derives the content.
class SolarTermResultContextExecutor {
  static const moduleId = 'solar_terms';
  static const resultSchemaVersion = 'solar-term-knowledge-result-v1';
  static const ruleVersion =
      'service-blob@d65480898a281fc4590dce0da198b49e4653f958;'
      'query-executor-blob@090bda6c00b067c177093927353507e6f62b5f86;'
      'knowledge-asset-blob@13ca91321f8b62f92faab11bb0df287b1e41215e;'
      'sxwnl_spa_dart@0.18.5';

  static Future<SolarTermResultContextExecution> executeWithSnapshot(
    Map<String, String> arguments,
  ) async {
    final term = arguments['term']?.trim();
    if (arguments.length != 1 ||
        arguments.keys.any((key) => key != 'term') ||
        term == null ||
        !SolarTermToolService.termNames.contains(term)) {
      return _failure(arguments, '必须明确选择二十四节气之一；不接受自由文本或额外参数。');
    }

    final normalized = {'term': term};
    final dispatch = await HeadlessToolDispatcher(
      featureAuthorizer: const DenyByDefaultFeatureAuthorizer(),
    ).executePlan(
      plan: ToolExecutionPlan(
        planId: 'context-rebuild-solar_terms',
        origin: InvocationOrigin.aiDispatch,
        steps: [
          ToolExecutionStep(
            toolId: moduleId,
            capabilityId: moduleId,
            arguments: normalized,
          ),
        ],
      ),
    );
    if (!dispatch.isCompleted || dispatch.results.length != 1) {
      return _failure(arguments, '上下文重建未通过完整执行计划校验；本次不生成 AI 快照。');
    }
    final result = dispatch.results.single;
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(normalized).isNotEmpty ||
        result.sourceIds.length != 2 ||
        !result.sourceIds.contains(SolarTermToolService.sourceId) ||
        !result.sourceIds.contains(SolarTermToolService.knowledgeSourceId) ||
        result.values['目标节气'] != term) {
      return SolarTermResultContextExecution(result: result);
    }

    final values = <String, Object?>{
      for (final entry in result.values.entries) entry.key: entry.value,
    };
    final missingFields = values.entries
        .where((entry) => entry.value == 'MISSING')
        .map((entry) => entry.key)
        .toList(growable: false);
    final baseSnapshot = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': const [
        SolarTermToolService.sourceId,
        SolarTermToolService.knowledgeSourceId,
      ],
      'input': <String, Object?>{
        'method': 'explicitSolarTerm',
        'arguments': normalized,
        'term': term,
        'timeBasis': '明确选择的节气知识条目；不随设备当前日期变化',
      },
      'result': <String, Object?>{
        'term': term,
        'values': values,
      },
      'units': const <String, Object?>{
        'result.太阳黄经': '度（°）',
        'result.进入当前节气天数': '天；指定节气查询未提供时标记 MISSING',
        'result.距下一节气天数': '天；指定节气查询未提供时标记 MISSING',
      },
      'missingFields': missingFields,
      'displaySummary':
          '$term · ${result.values['公历约期'] ?? 'MISSING'} · ${result.values['太阳黄经'] ?? 'MISSING'}',
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;

    return SolarTermResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static SolarTermResultContextExecution _failure(
    Map<String, String> arguments,
    String message,
  ) {
    return SolarTermResultContextExecution(
      result: AssistantToolResult(
        toolId: moduleId,
        title: '节气养生',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '节气上下文参数不符合约束；本次没有生成可供 AI 使用的快照。',
      ),
    );
  }

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
