import '../models/assistant_tool_result.dart';
import 'ziwuliuzhu_calculation_service.dart';

/// Headless adapter over the same ZiWuLiuZhu calculation used by the
/// legacy screen. It never changes any GanZhi or open-point rule.
class ZiWuLiuZhuToolExecutor {
  static const sourceId = 'local-engine:ziwuliuzhu';
  static const referenceSourceId = 'local-data:ziwuliuzhu-reference-tables';

  static Map<String, String> prepareExecutionArguments(
    Map<String, String> arguments, {
    DateTime? now,
  }) {
    final prepared = <String, String>{...arguments};
    if (prepared.containsKey('at')) return Map.unmodifiable(prepared);

    final date = prepared['date'];
    final time = prepared['time'];
    if (date != null && time != null) {
      final candidate = '${date}T$time';
      if (ZiWuLiuZhuCalculationService.parseLocalAt(candidate) != null) {
        prepared['at'] = candidate;
      }
    } else if (date == null && time == null) {
      prepared['at'] =
          ZiWuLiuZhuCalculationService.formatLocalAt(now ?? DateTime.now());
    } else if (date == null && time != null) {
      final current = now ?? DateTime.now();
      final candidate = '${current.year.toString().padLeft(4, '0')}-'
          '${current.month.toString().padLeft(2, '0')}-'
          '${current.day.toString().padLeft(2, '0')}T$time';
      if (ZiWuLiuZhuCalculationService.parseLocalAt(candidate) != null) {
        prepared['date'] = candidate.substring(0, 10);
        prepared['at'] = candidate;
      }
    }
    return Map.unmodifiable(prepared);
  }

  static List<String> validateArguments(Map<String, String> arguments) {
    const allowed = {'at', 'date', 'time'};
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      return const ['包含未声明的子午流注计算参数'];
    }
    final at = arguments['at'];
    if (at == null || at.isEmpty) return const ['缺少完整的设备本地日期和时间'];
    if (ZiWuLiuZhuCalculationService.parseLocalAt(at) == null) {
      return const ['计算时间必须为有效的本地时间 YYYY-MM-DDTHH:mm（不含时区偏移）'];
    }
    final parsed = ZiWuLiuZhuCalculationService.parseLocalAt(at)!;
    final date = arguments['date'];
    if (date != null &&
        date != '${parsed.year.toString().padLeft(4, '0')}-'
            '${parsed.month.toString().padLeft(2, '0')}-'
            '${parsed.day.toString().padLeft(2, '0')}') {
      return const ['日期与最终计算时间不匹配'];
    }
    final time = arguments['time'];
    if (time != null &&
        time != '${parsed.hour.toString().padLeft(2, '0')}:'
            '${parsed.minute.toString().padLeft(2, '0')}') {
      return const ['时刻与最终计算时间不匹配'];
    }
    return const [];
  }

  static AssistantToolResult execute(Map<String, String> arguments) {
    final errors = validateArguments(arguments);
    if (errors.isNotEmpty) {
      return AssistantToolResult(
        toolId: 'ziwu_liuzhu',
        title: '子午流注时辰开穴结果',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': errors.join('；')},
        arguments: Map.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行计算。',
      );
    }

    final at = ZiWuLiuZhuCalculationService.parseLocalAt(arguments['at']!);
    if (at == null) {
      return AssistantToolResult(
        toolId: 'ziwu_liuzhu',
        title: '子午流注时辰开穴结果',
        status: AssistantToolExecutionStatus.failed,
        values: const {'未执行原因': '本地计算时间无效'},
        arguments: Map.unmodifiable(arguments),
        disclaimer: '本次没有执行计算。',
      );
    }
    final result = ZiWuLiuZhuCalculationService.calculate(at);
    return AssistantToolResult(
      toolId: 'ziwu_liuzhu',
      title: '子午流注时辰开穴计算结果',
      values: result.values,
      arguments: Map.unmodifiable(arguments),
      sourceIds: const [sourceId, referenceSourceId],
      disclaimer: '结果由 App 原有子午流注引擎和内置参考表生成；默认经度 120E/纬度 30N，子时按 23:00 换日，未启用真太阳时。开穴结果属于传统经络时辰计算资料，不构成疾病诊断、针刺处方或个体治疗建议。',
    );
  }
}
