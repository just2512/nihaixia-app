import '../models/assistant_tool_result.dart';
import 'dosage_conversion_service.dart';
import 'tool_argument_support.dart';

/// Headless adapter over the same pure unit converter used by
/// DosageConverterScreen. It intentionally excludes drug dose advice.
class DosageToolExecutor {
  static const sourceId = 'local-engine:dosage-conversion';
  static const factorsSourceId = 'local-data:dosage-conversion-factors';

  static List<String> validateArguments(Map<String, String> arguments) =>
      ToolArgumentSupport.validateDosageArguments(arguments);

  static AssistantToolResult execute(Map<String, String> arguments) {
    final errors = validateArguments(arguments);
    if (errors.isNotEmpty) {
      return AssistantToolResult(
        toolId: 'dosage',
        title: '经方度量衡单位换算',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': errors.join('；')},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行换算。',
      );
    }

    final conversion = DosageConversionService.convert(
      input: arguments['value']!,
      unit: arguments['unit']!,
      standard: arguments['standard'],
    );
    if (conversion == null) {
      return AssistantToolResult(
        toolId: 'dosage',
        title: '经方度量衡单位换算',
        status: AssistantToolExecutionStatus.failed,
        values: const {'未执行原因': 'App 换算函数未返回有效结果'},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '本次没有执行换算。',
      );
    }

    return AssistantToolResult(
      toolId: 'dosage',
      title: '经方度量衡单位换算',
      values: {
        '度量标准': DosageConversionService.isWeightUnit(conversion.unit)
            ? DosageConversionService.standardLabel(conversion.standard)
            : '不参与容量/长度换算',
        '输入数值': conversion.input,
        '原始单位': conversion.unit,
        '换算结果': conversion.formattedValue,
        '目标单位': conversion.outputUnit,
        '换算类型': DosageConversionService.isWeightUnit(conversion.unit)
            ? '重量换算'
            : DosageConversionService.isVolumeUnit(conversion.unit)
                ? '容量换算'
                : '长度换算',
        '业务范围': '仅单位换算；不计算药物处方剂量',
      },
      arguments: Map<String, String>.unmodifiable(arguments),
      sourceIds: const [sourceId, factorsSourceId],
      disclaimer: '结果由 App 原有单位换算常数执行，仅为度量衡单位换算，不构成临床剂量、处方或个体用药建议。页面中的药物特殊换算表和体质剂量参考未参与本次计算。',
    );
  }
}
