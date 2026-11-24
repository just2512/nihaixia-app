import '../models/assistant_tool_result.dart';
import '../models/tool_execution_plan.dart';
import 'ai_tool_result_snapshot.dart';
import 'headless_tool_dispatcher.dart';
import 'shousheng_debt_tool_service.dart';

class ShoushengDebtResultContextExecution {
  const ShoushengDebtResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Captures one of the two explicitly selected Shousheng lookup traditions.
/// Exact birth date/time remain local for replay verification and are removed
/// from the model prompt by AiContextPromptBuilder.
class ShoushengDebtResultContextExecutor {
  static const moduleId = 'shousheng_debt';
  static const resultSchemaVersion = 'shousheng-debt-structured-result-v1';
  static const ruleVersion =
      'tool-executor-blob@c871e62090c7d8103b1d73bcd5128b2cb0b0b35f;'
      'data-access-blob@4bdda8b779f09f038a774f76b2ed51d39a71ed49;'
      'luku-asset-blob@0b80b1bf2f0b73f8d2074012d9a4f74338b75c59;'
      'wudou-asset-blob@a36a50c82e4be1bfec8242d3321412021e36fd73;'
      'bazi-service-blob@724e5dcf4c32c22d62c5f2a1db50e81f8a0f8ffe;'
      'settings-blob@2b1b4739e58d463d91037961886f71403e1551f4;'
      'bazi_core@0.6.7;ziwei_core@0.13.0';

  static Future<ShoushengDebtResultContextExecution> executeWithSnapshot(
    Map<String, String> arguments,
  ) async {
    const allowed = {'birth_date', 'birth_time', 'method'};
    if (arguments.length != 3 ||
        arguments.keys.any((key) => !allowed.contains(key))) {
      return _failure(arguments, '只接受 birth_date、birth_time 和 method 三个明确输入字段。');
    }
    final method = arguments['method'];
    if (!ShoushengDebtToolService.methods.contains(method)) {
      return _failure(arguments, '查询体系必须明确选择 luku 或 wudou。');
    }

    final dispatch = await const HeadlessToolDispatcher().executePlan(
      plan: ToolExecutionPlan(
        planId: 'context-rebuild-shousheng_debt',
        origin: InvocationOrigin.aiDispatch,
        steps: [
          ToolExecutionStep(
            toolId: moduleId,
            capabilityId: moduleId,
            arguments: arguments,
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
        result.validateArgumentsMatch(arguments).isNotEmpty ||
        result.arguments.length != 3 ||
        result.arguments['method'] != method ||
        result.sourceIds.length != 2 ||
        result.sourceIds[0] != ShoushengDebtToolService.sourceId) {
      return ShoushengDebtResultContextExecution(result: result);
    }

    final expectedDataSource = method == 'luku'
        ? ShoushengDebtToolService.lukuDataSourceId
        : ShoushengDebtToolService.wudouDataSourceId;
    if (result.sourceIds[1] != expectedDataSource) {
      return ShoushengDebtResultContextExecution(result: result);
    }
    final expectedFields = method == 'luku'
        ? const ['禄库曹官数据', '本命元辰数据']
        : const ['五斗本命钱数据', '十二库神数据', '口径说明'];
    if (expectedFields.any((field) =>
        result.values[field] == null ||
        result.values[field]!.isEmpty ||
        result.values[field] == 'MISSING')) {
      return ShoushengDebtResultContextExecution(result: result);
    }

    final normalizedArguments =
        Map<String, String>.unmodifiable(result.arguments);
    final values = <String, Object?>{
      for (final entry in result.values.entries) entry.key: entry.value,
    };
    final missingFields = values.entries
        .where((entry) =>
            entry.value == 'MISSING' ||
            (entry.value is String && (entry.value as String).isEmpty))
        .map((entry) => entry.key)
        .toList(growable: false);
    if (!values.containsKey('真太阳时校正') ||
        !values.containsKey('早晚子时区分') ||
        !{'开启', '关闭'}.contains(values['真太阳时校正']) ||
        !{'开启', '关闭'}.contains(values['早晚子时区分'])) {
      return _failure(arguments, '本次执行使用的历法设置无法确认；不生成 AI 快照。');
    }

    final baseSnapshot = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': List<String>.unmodifiable(result.sourceIds),
      'input': <String, Object?>{
        'method': method,
        'arguments': normalizedArguments,
        'settings': <String, Object?>{
          'useTrueSolarTime': values['真太阳时校正'] == '开启',
          'distinguishZiShi': values['早晚子时区分'] == '开启',
        },
      },
      'result': <String, Object?>{
        'values': values,
        'disclaimer': result.disclaimer ?? '道教文献研究与民俗文化参考。',
      },
      'units': const <String, Object?>{
        'result.values.禄库曹官数据': '原文结构化字段；金额单位按来源文献标注为贯',
        'result.values.本命元辰数据': '原文结构化字段；金额单位按来源文献标注为贯',
        'result.values.五斗本命钱数据': '原文结构化字段；金额单位按来源文献标注为贯',
        'result.values.十二库神数据': '原文结构化字段；金额单位按来源文献标注为贯',
      },
      'missingFields': missingFields,
      'displaySummary':
          '${values['查询体系'] ?? 'MISSING'} · ${method == 'luku' ? values['年支'] : values['日干']} · ${method == 'luku' ? '禄库/本命元辰' : '五斗/十二库神'}',
      'privacy': const <String, Object?>{
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
    return ShoushengDebtResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static ShoushengDebtResultContextExecution _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      ShoushengDebtResultContextExecution(
        result: AssistantToolResult(
          toolId: moduleId,
          title: '受生债查询',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': message},
          arguments: Map<String, String>.unmodifiable(arguments),
          disclaimer: '上下文参数、来源或设置未通过校验；本次没有生成可供 AI 使用的结果快照。',
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
