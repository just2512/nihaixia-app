import 'dart:math';

import '../data/sanshan_lingqian_data.dart';
import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'sanshan_lingqian_tool_executor.dart';

class SanshanLingqianResultContextExecution {
  const SanshanLingqianResultContextExecution({
    required this.sign,
    required this.result,
    this.structuredSnapshot,
  });

  final LingqianSign? sign;
  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      sign != null &&
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Captures one App-owned random draw. Replay resolves the selected local
/// catalogue entry by ID; it never performs another random draw.
class SanshanLingqianResultContextExecutor {
  static const moduleId = 'sanshan_lingqian';
  static const resultSchemaVersion = 'sanshan-lingqian-structured-result-v1';
  static const ruleVersion =
      'tool-executor-blob@f92035c5fe23e179833e2b04d48b4b9536cd1b23;'
      'data-asset-blob@beeb5edea611e34655731845c336af0f096d9950;'
      'draw-owner=app-local;catalogue=92-signs';

  static Future<SanshanLingqianResultContextExecution> drawWithSnapshot({
    Random? random,
  }) async {
    final sign = SanshanLingqianToolExecutor.draw(random: random);
    return executeForSignId(sign.id);
  }

  static Future<SanshanLingqianResultContextExecution> executeForSignId(
    int signId,
  ) async {
    final matches = kSanShanLingqian.where((entry) => entry.id == signId);
    if (matches.length != 1) {
      return _failure(signId, '签号不属于当前本地 92 签签谱；拒绝生成结果快照。');
    }
    final sign = matches.single;
    final result = SanshanLingqianToolExecutor.resultForSign(sign);
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(const {}).isNotEmpty ||
        result.arguments.isNotEmpty ||
        result.sourceIds.length != 1 ||
        result.sourceIds.single !=
            '\${SanshanLingqianToolExecutor.dataSourcePrefix}$signId' ||
        result.values['签号'] != sign.id.toString() ||
        result.values['签题'] != sign.title ||
        result.values['签诗'] != sign.verse ||
        result.values['签级'] != sign.luck.label) {
      return SanshanLingqianResultContextExecution(result: result);
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
      'sourceIds': <String>[
        '\${SanshanLingqianToolExecutor.dataSourcePrefix}$signId',
      ],
      'input': <String, Object?>{
        'method': 'appRandomDraw',
        'arguments': const <String, Object?>{},
        'selectedSignId': signId,
        'selectionOwner': 'APP_LOCAL_ONLY',
      },
      'result': <String, Object?>{
        'values': values,
        'disclaimer': result.disclaimer ??
            '潮汕客家民间信仰与签谱文化参考，不是现实吉凶保证或决策依据。',
      },
      'units': const <String, Object?>{
        'result.values.签号': '本地签谱序号（1-92）',
        'result.values.签题': '签题文本',
        'result.values.签诗': '本地签谱原文',
        'result.values.签级': '签谱所载传统等级，不是现实预测',
      },
      'missingFields': missingFields,
      'displaySummary': '\${values['签号'] ?? 'MISSING'} · '
          '\${values['签题'] ?? 'MISSING'} · \${values['签级'] ?? 'MISSING'}',
      'provenance': <String, Object?>{
        'catalogue': '广东揭西三山国王祖庙传承 92 签签谱',
        'selection': '签号由 App 本地随机抽取；模型不得指定、替换或重抽',
      },
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;
    return SanshanLingqianResultContextExecution(
      sign: sign,
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static SanshanLingqianResultContextExecution _failure(
    int signId,
    String message,
  ) =>
      SanshanLingqianResultContextExecution(
        sign: null,
        result: AssistantToolResult(
          toolId: moduleId,
          title: '三山国王灵签',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': message},
          sourceIds: const [],
          arguments: {'sign_id': signId.toString()},
          disclaimer: '签谱身份或来源未通过校验；本次没有生成可供 AI 使用的快照。',
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
