import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'ziwuliuzhu_calculation_service.dart';
import 'tool_argument_support.dart';

class ZiWuLiuZhuToolExecution {
  const ZiWuLiuZhuToolExecution({
    required this.result,
    this.calculationResult,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final ZiWuLiuZhuCalculationResult? calculationResult;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null &&
      calculationResult != null;
}

/// Headless adapter over the same deterministic calculation used by the legacy
/// ZiWuLiuZhu page. Snapshot creation serializes the existing calculation; it
/// does not add, replace, or reinterpret any open-point rule.
class ZiWuLiuZhuToolExecutor {
  static const moduleId = 'ziwu_liuzhu';
  static const sourceId = 'local-engine:ziwuliuzhu';
  static const referenceSourceId = 'local-data:ziwuliuzhu-reference-tables';
  static const resultSchemaVersion = 'ziwuliuzhu-structured-result-v1';
  static const ruleVersion =
      'engine-blob@c78775821e9295150b5b1e5592810a997d2213b4;'
      'calculation-service-blob@7a472f0112f97f08680fc0fdc4773ae99de7c288;'
      'bazi_core@0.6.7;ziwei_core@0.13.0';

  static Map<String, String> prepareExecutionArguments(
    Map<String, String> arguments, {
    DateTime? now,
  }) =>
      ToolArgumentSupport.prepareZiWuLiuZhuArguments(arguments, now: now);

  static List<String> validateArguments(Map<String, String> arguments) =>
      ToolArgumentSupport.validateZiWuLiuZhuArguments(arguments);

  static AssistantToolResult execute(Map<String, String> arguments) =>
      executeWithSnapshot(arguments).result;

  static ZiWuLiuZhuToolExecution executeWithSnapshot(
    Map<String, String> arguments,
  ) {
    final errors = validateArguments(arguments);
    if (errors.isNotEmpty) {
      return _failedExecution(arguments, errors.join('；'));
    }

    final atText = arguments['at']!;
    final at = ZiWuLiuZhuCalculationService.parseLocalAt(atText);
    if (at == null) {
      return _failedExecution(arguments, '本地计算时间无效');
    }

    final calculation = ZiWuLiuZhuCalculationService.calculate(at);
    final values = calculation.values;
    final result = <String, Object?>{
      'dayGanZhi': calculation.dayGanZhi,
      'hourGanZhi': calculation.hourGanZhi,
      'shichen': calculation.shichen,
      'timeRange': calculation.timeRange,
      'meridian': calculation.meridian,
      'methods': <String, Object?>{
        'naZi': <String, Object?>{
          'dayGanZhi': calculation.dayGanZhi,
          'hourGanZhi': calculation.hourGanZhi,
          'shichen': calculation.shichen,
          'timeRange': calculation.timeRange,
          'meridian': calculation.meridian,
          'benXue': calculation.benXue,
          'dayOrgan': calculation.dayOrgan,
          'fiveChange': calculation.wuMenInfo,
        },
        'naJia': <String, Object?>{
          'status': values.containsKey('纳甲穴位')
              ? 'AVAILABLE'
              : 'NOT_APPLICABLE',
          'selection': values['纳甲法'] ?? 'NOT_APPLICABLE',
          'summary': calculation.najiaText,
          if (values.containsKey('纳甲穴位'))
            'point': values['纳甲穴位'],
          if (values.containsKey('纳甲经络'))
            'meridian': values['纳甲经络'],
          if (values.containsKey('纳甲穴性'))
            'pointCategory': values['纳甲穴性'],
          if (values.containsKey('返本还原原穴'))
            'yuanPoint': values['返本还原原穴'],
        },
        'lingGui': <String, Object?>{
          'status': 'SUCCESS',
          'summary': calculation.lingguiText,
          'gua': values['灵龟卦'],
          'mainPoint': values['灵龟主穴'],
          'mainMeridian': values['灵龟主脉'],
          'pairedPoint': values['灵龟配穴'],
          'pairedMeridian': values['灵龟配脉'],
          'calculationSteps': values['灵龟计算步骤'],
        },
        'feiTeng': <String, Object?>{
          'status': values.containsKey('飞腾开穴')
              ? 'AVAILABLE'
              : 'NOT_APPLICABLE',
          'summary': calculation.feitengText,
          if (values.containsKey('飞腾卦')) 'gua': values['飞腾卦'],
          if (values.containsKey('飞腾开穴')) 'point': values['飞腾开穴'],
        },
      },
      'values': values,
    };

    final baseSnapshot = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': const [sourceId, referenceSourceId],
      'input': <String, Object?>{
        'method': 'deviceLocalDateTime',
        'arguments': <String, Object?>{'at': atText},
        'executionDate': atText.substring(0, 10),
        'timeBasis': 'device-local wall-clock; YYYY-MM-DDTHH:mm; no UTC offset',
        'rules': const <String, Object?>{
          'longitude': 120,
          'latitude': 30,
          'useTrueSolarTime': false,
          'ratHourMode': 'noSplit',
          'ziHourDayBoundary': '23:00',
        },
      },
      'result': result,
      'units': const <String, Object?>{
        'input.arguments.at': 'App 设备本地墙钟时间，YYYY-MM-DDTHH:mm，不含时区偏移',
        'result.shichen': '地支时辰',
        'result.timeRange': '时辰对应的本地时段',
        'result.nazi.meridian': '经络名称',
        'result.nazi.benXue': '穴位名称',
        'result.methods.naJia.point': '穴位名称；无适用开穴时状态为 NOT_APPLICABLE',
        'result.methods.lingGui.mainPoint': '主穴名称',
        'result.methods.lingGui.pairedPoint': '配穴名称',
        'result.methods.feiTeng.point': '穴位名称；无对应时状态为 NOT_APPLICABLE',
      },
      'missingFields': const <String>[],
      'displaySummary': calculation.summary,
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;

    final assistantResult = AssistantToolResult(
      toolId: moduleId,
      title: '子午流注时辰开穴计算结果',
      status: AssistantToolExecutionStatus.succeeded,
      values: calculation.values,
      arguments: Map.unmodifiable(arguments),
      sourceIds: const [sourceId, referenceSourceId],
      disclaimer:
          '结果由 App 原有子午流注引擎和内置参考表生成；默认经度 120E/30N，子时按 23:00 换日，未启用真太阳时。开穴结果属于传统经络时辰计算资料，不构成疾病诊断、针刺处方或个体治疗建议。',
    );

    return ZiWuLiuZhuToolExecution(
      result: assistantResult,
      calculationResult: calculation,
      structuredSnapshot: snapshot,
    );
  }

  static ZiWuLiuZhuToolExecution _failedExecution(
    Map<String, String> arguments,
    String reason,
  ) {
    return ZiWuLiuZhuToolExecution(
      result: AssistantToolResult(
        toolId: moduleId,
        title: '子午流注时辰开穴结果',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行计算。',
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
