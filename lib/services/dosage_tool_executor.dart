import '../models/assistant_tool_result.dart';
import 'dosage_conversion_service.dart';

/// Headless adapter for the exact unit conversion already used by
/// DosageConverterScreen. It intentionally excludes the screen's special-herb
/// reference tables and never produces individual dose or prescription advice.
class DosageToolExecutor {
  static const String sourceId = 'local-engine:dosage-converter';
  static const String dataSourceId = 'local-data:dosage-conversion-factors';

  static AssistantToolResult execute(Map<String, String> arguments) {
    const allowedKeys = {'amount', 'unit', 'standard'};
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      return _failure(arguments, '包含未声明的换算参数；未执行计算。');
    }

    final amount = arguments['amount']?.trim();
    final unit = arguments['unit']?.trim();
    final standard = arguments['standard']?.trim();

    if (amount == null || amount.isEmpty) {
      return _failure(arguments, '缺少待换算数量；未执行计算。');
    }
    final parsedAmount = double.tryParse(amount);
    if (parsedAmount == null || !parsedAmount.isFinite || parsedAmount <= 0) {
      return _failure(arguments, '数量必须是有限且大于零的数字；未执行计算。');
    }
    if (unit == null || unit.isEmpty || !DosageConversionService.isKnownUnit(unit)) {
      return _failure(arguments, '缺少或不支持单位；请提供两、铢、斤、石、钱、升、合、圭、撮、尺或寸。');
    }
    if (DosageConversionService.needsWeightStandard(unit) &&
        (standard == null || standard.isEmpty)) {
      return _failure(arguments, '重量单位必须明确指定汉制、台制或唐制；未执行计算。');
    }
    if (standard != null &&
        !DosageConversionService.standardLabels.containsKey(standard)) {
      return _failure(arguments, '度量标准只能是汉制、台制或唐制；未执行计算。');
    }

    final output = DosageConversionService.convert(
      amount: amount,
      unit: unit,
      standard: standard,
    );
    if (output == null) {
      return _failure(
        arguments,
        '该单位在所选标准下没有可用换算常数，或计算结果超出有效范围；未执行计算。',
      );
    }

    final values = <String, String>{
      '换算类别': output.category,
      '度量标准': output.standardLabel,
      '输入数量': amount,
      '输入单位': output.inputUnit,
      '换算数值': output.formattedNumber,
      '目标单位': output.targetUnit,
      '换算结果': output.formattedResult,
      '标准影响': output.standardAffectsCalculation
          ? '重量换算使用所选的汉制/台制/唐制系数。'
          : '容量/长度换算沿用原页面常数，不受重量标准选择影响。',
      '计算范围': '仅为度量衡单位换算；未使用特殊药物容积/枚数对照表。',
    };

    return AssistantToolResult(
      toolId: 'dosage',
      title: '经方度量衡单位换算结果',
      values: Map<String, String>.unmodifiable(values),
      sourceIds: const [sourceId, dataSourceId],
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '这是 App 原有度量衡常数的单位换算，不是中药处方、临床剂量或个体用药建议。',
    );
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'dosage',
        title: '经方度量衡单位换算',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行换算。',
      );
}
