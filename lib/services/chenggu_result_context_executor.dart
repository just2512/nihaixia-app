import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'chenggu_tool_executor.dart';

class ChengguResultContextExecution {
  const ChengguResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Source-binds one actual Chenggu calculation. Exact birth details stay
/// local in the immutable snapshot for replay verification, then are redacted
/// from the model prompt.
class ChengguResultContextExecutor {
  static const moduleId = 'chenggu';
  static const resultSchemaVersion = 'chenggu-structured-result-v1';
  static const ruleVersion =
      'tool-executor-blob@150a932f16fef1d5802254b0c1d3d5b7d507c77b;'
      'data-access-blob@c4d1d4f3d35cb5c6ae559d7a7f2d7c615f583de8;'
      'data-asset-blob@7b6e22ea51cb387b040ea248d50a1b24e81aeb1e;'
      'bazi-service-blob@724e5dcf4c32c22d62c5f2a1db50e81f8a0f8ffe;'
      'settings-blob@2b1b4739e58d463d91037961886f71403e1551f4;'
      'bazi_core@0.6.7;sxwnl_spa_dart@0.18.5;ziwei_core@0.13.0';

  static Future<ChengguResultContextExecution> executeWithSnapshot(
    Map<String, String> arguments,
  ) async {
    const allowed = {'birth_date', 'birth_time'};
    if (arguments.length != 2 ||
        arguments.keys.any((key) => !allowed.contains(key))) {
      return _failure(arguments, '只接受明确的公历 birth_date 与当地钟表 birth_time。');
    }

    final result = await ChengguToolExecutor.execute(arguments);
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(arguments).isNotEmpty ||
        result.sourceIds.length != 2 ||
        result.sourceIds[0] != ChengguToolExecutor.sourceId ||
        result.sourceIds[1] != ChengguToolExecutor.dataSourceId) {
      return ChengguResultContextExecution(result: result);
    }

    const requiredFields = [
      '出生公历',
      '出生农历口径',
      '出生钟表时辰',
      '称骨计算时柱地支',
      '真太阳时校正',
      '早晚子时区分',
      '总骨重',
      '称骨歌诀标题',
      '称骨歌诀',
    ];
    if (requiredFields.any((field) =>
        result.values[field] == null ||
        result.values[field]!.isEmpty ||
        result.values[field] == 'MISSING')) {
      return _failure(arguments, '称骨结果缺少完整的原始字段；本次不生成 AI 快照。');
    }
    if (!{'开启', '关闭'}.contains(result.values['真太阳时校正']) ||
        !{'开启', '关闭'}.contains(result.values['早晚子时区分'])) {
      return _failure(arguments, '称骨执行时使用的历法设置无法确认。');
    }

    final normalizedArguments =
        Map<String, String>.unmodifiable(result.arguments);
    final values = <String, Object?>{
      for (final entry in result.values.entries)
        entry.key: entry.key == '称骨说明' && entry.value.isEmpty
            ? 'MISSING'
            : entry.value,
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
        ChengguToolExecutor.sourceId,
        ChengguToolExecutor.dataSourceId,
      ],
      'input': <String, Object?>{
        'method': 'explicitBirthDateTime',
        'arguments': normalizedArguments,
        'settings': <String, Object?>{
          'useTrueSolarTime': result.values['真太阳时校正'] == '开启',
          'distinguishZiShi': result.values['早晚子时区分'] == '开启',
        },
        'calculationRules': const <String, Object?>{
          'yearGanZhi': '由 App 八字引擎按当前立春/年柱规则计算',
          'lunarDate': '公历出生日期正午换算农历月日',
          'calculationHourBranch': 'App 八字引擎按保存的真太阳时及早晚子时设置计算',
          'weightUnit': '1两 = 10钱；表中 qian 为总钱数',
        },
      },
      'result': <String, Object?>{
        'values': values,
        'disclaimer': result.disclaimer ?? '传统民俗文化研究参考，非科学预测。',
      },
      'units': const <String, Object?>{
        'result.values.出生农历口径': '农历年干支、月、日',
        'result.values.出生钟表时辰': '当地钟表时辰地支',
        'result.values.称骨计算时柱地支': 'App 八字引擎按历法设置计算的时柱地支',
        'result.values.总骨重': '两、钱；1两 = 10钱',
      },
      'missingFields': missingFields,
      'displaySummary':
          (values['总骨重'] ?? 'MISSING').toString() + ' · ' +
          (values['称骨歌诀标题'] ?? 'MISSING').toString(),
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
    return ChengguResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static ChengguResultContextExecution _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      ChengguResultContextExecution(
        result: AssistantToolResult(
          toolId: moduleId,
          title: '袁天罡称骨',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': message},
          arguments: Map<String, String>.unmodifiable(arguments),
          disclaimer: '参数、来源或数据未通过校验；本次没有生成可供 AI 使用的结果快照。',
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
