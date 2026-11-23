import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'headless_tool_dispatcher.dart';
import 'dosage_tool_service.dart';

class DosageResultContextExecution {
  const DosageResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Captures the exact output from the existing deterministic unit converter.
/// It deliberately excludes the page's special drug tables and dose references.
class DosageResultContextExecutor {
  static const moduleId = 'dosage';
  static const resultSchemaVersion = 'dosage-structured-result-v1';
  static const ruleVersion =
      'tool-executor-blob@b015b3bbfb30e72c0e286f586a78cce16083875e;'
      'conversion-service-blob@41a11afe9207c5b4cd9f6f7e53216aa6d81d2d07';

  static DosageResultContextExecution executeWithSnapshot({
    required Map<String, String> arguments,
  }) {
    final safeArguments = Map<String, String>.unmodifiable(arguments);
    final result = HeadlessToolDispatcher.executeSync(toolId: 'dosage', arguments: safeArguments);
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(safeArguments).isNotEmpty ||
        result.arguments.length != safeArguments.length ||
        result.arguments.entries.any(
          (entry) => safeArguments[entry.key] != entry.value,
        ) ||
        result.sourceIds.length != 2 ||
        result.sourceIds[0] != DosageToolService.sourceId ||
        result.sourceIds[1] != DosageToolService.factorsSourceId ||
        result.values['业务范围'] != '仅单位换算；不计算药物处方剂量' ||
        result.values['换算结果'] is! String ||
        result.values['目标单位'] is! String) {
      return DosageResultContextExecution(result: result);
    }

    final values = <String, Object?>{
      for (final entry in result.values.entries) entry.key: entry.value,
    };
    final baseSnapshot = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': <String>[
        DosageToolService.sourceId,
        DosageToolService.factorsSourceId,
      ],
      'input': <String, Object?>{
        'method': 'explicitUnitConversion',
        'arguments': <String, String>{
          for (final entry in safeArguments.entries) entry.key: entry.value,
        },
      },
      'result': <String, Object?>{
        'title': result.title,
        'values': values,
        'disclaimer': result.disclaimer ??
            '仅为 App 单位换算结果，不构成临床剂量、处方或个体用药建议。',
      },
      'units': const <String, Object?>{
        'input.value': '用户输入的正有限数字',
        'input.unit': 'App 当前换算器支持的原始单位',
        'input.standard': '重量换算使用的度量标准；容量和长度换算不依赖该标准',
        'result.values.换算结果': '按 App 原有精度格式化的换算数值',
        'result.values.目标单位': 'App 换算器指定的目标单位',
      },
      'missingFields': const <String>[],
      'displaySummary':
          '${safeArguments['value'] ?? 'MISSING'} '
          '${safeArguments['unit'] ?? 'MISSING'} → '
          '${values['换算结果'] ?? 'MISSING'} '
          '${values['目标单位'] ?? 'MISSING'}',
      'provenance': <String, Object?>{
        'calculation': 'DosageConversionService；App 原有纯函数',
        'factorSource': DosageToolService.factorsSourceId,
        'scope': '只包含重量、容量或长度单位换算；不包含药物特殊换算表或任何剂量建议',
      },
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;
    return DosageResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
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
