import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'yuxiaji_omen_time.dart';
import 'yuxiaji_omen_tool_service.dart';

class YuxiajiOmenResultContextExecution {
  const YuxiajiOmenResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Captures one device-local clock reading and the exact corresponding
/// twelve-hour folk-text lookup. Replay uses the recorded local wall time.
class YuxiajiOmenResultContextExecutor {
  static const moduleId = 'yuxiaji_omen';
  static const resultSchemaVersion = 'yuxiaji-omen-structured-result-v1';
  static const ruleVersion =
      'tool-executor-blob@3aa34cf353631ceb6dcfa7df0d4adb901b355ddc;'
      'data-asset-blob@740e7e605f9e0b3608dde5f6933247e7fcba5cb4;'
      'time-rule-blob@ac473d000e9283e8137da2108b088bd8bd65f207';

  static YuxiajiOmenResultContextExecution executeWithSnapshot({
    required DateTime observedAt,
  }) {
    if (observedAt.isUtc) {
      return _failure('必须使用 App 设备本地时间，不接受 UTC 时间输入。');
    }
    final result = YuxiajiOmenToolService.execute(
      const {},
      clock: () => observedAt,
    );
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(const {}).isNotEmpty ||
        result.arguments.isNotEmpty ||
        result.sourceIds.length != 1 ||
        result.sourceIds.single != YuxiajiOmenToolService.sourceId ||
        result.values['App 本机日期时间'] != observedAt.toIso8601String() ||
        result.values['本机 UTC 偏移分钟'] !=
            observedAt.timeZoneOffset.inMinutes.toString() ||
        result.values['当前时辰'] != shiChenLabel(shiChenIndexOf(observedAt)) ||
        result.values['《玉匣记》当前时辰身兆条目']?.isNotEmpty != true) {
      return YuxiajiOmenResultContextExecution(result: result);
    }

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
      'sourceIds': const [YuxiajiOmenToolService.sourceId],
      'input': <String, Object?>{
        'method': 'deviceLocalDateTime',
        'arguments': const <String, Object?>{},
        'at': observedAt.toIso8601String(),
        'utcOffsetMinutes': observedAt.timeZoneOffset.inMinutes,
        'clockOwner': 'APP_DEVICE_LOCAL',
      },
      'result': <String, Object?>{
        'title': result.title,
        'values': values,
        'disclaimer': result.disclaimer ??
            '传统民俗文化文本参考；不是科学预测或医学诊断。',
      },
      'units': const <String, Object?>{
        'input.at': '设备本地 ISO 8601 日期时间（不含 UTC 后缀）',
        'input.utcOffsetMinutes': '抽取时设备本地 UTC 偏移分钟',
        'result.values.当前时辰': '十二地支时辰',
        'result.values.《玉匣记》当前时辰身兆条目': '本地原始民俗文本',
      },
      'missingFields': missingFields,
      'displaySummary':
          '${values['当前时辰'] ?? 'MISSING'} · 当前时辰身兆条目（本地）',
      'provenance': <String, Object?>{
        'textSource': '《玉匣记》杂占篇·身体兆占本地数据资产',
        'clockSource': 'App 设备本地时钟',
        'scope': '仅包含十二时辰身兆文本，不包含特殊占法或用户自述症状',
      },
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;

    return YuxiajiOmenResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static YuxiajiOmenResultContextExecution _failure(String reason) =>
      YuxiajiOmenResultContextExecution(
        result: AssistantToolResult(
          toolId: moduleId,
          title: '玉匣灵兆',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': reason},
          sourceIds: const [],
          arguments: const {},
          disclaimer: '时间参数未通过校验；本次没有生成可供 AI 使用的结果快照。',
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
