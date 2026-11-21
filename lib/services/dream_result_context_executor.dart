import '../data/dream_data.dart';
import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'dream_tool_executor.dart';

class DreamResultContextExecution {
  const DreamResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// Creates a source-bound snapshot only after the user selects one exact
/// bundled DreamEntry.id. It deliberately does not accept free-text dream
/// descriptions or search-result candidate lists.
class DreamResultContextExecutor {
  static const moduleId = 'dream';
  static const resultSchemaVersion = 'dream-entry-structured-result-v1';
  static const ruleVersion =
      'dream-data-blob@ceaf925eb76f25c4df6488c0934520e4995fd409;'
      'dream-tool-executor-blob@ccbe617ac4ce44b990ac29f5d9c55c66ec0f4adb;'
      'dream-data-entry-count@412;'
      'selection-contract@explicit-entry-id-v1';

  static DreamResultContextExecution executeWithSnapshot({
    required String selectedEntryId,
  }) {
    final id = selectedEntryId.trim();
    if (id.isEmpty || id != selectedEntryId) {
      return _failure(selectedEntryId, '必须明确选择一个本地梦境词条 ID。');
    }

    final matches =
        kDreamEntries.where((entry) => entry.id == id).toList(growable: false);
    if (matches.length != 1) {
      return _failure(
        selectedEntryId,
        matches.isEmpty
            ? '所选词条 ID 不存在于当前本地数据集。'
            : '所选词条 ID 在当前本地数据集中不唯一；拒绝生成解释快照。',
      );
    }

    final entry = matches.single;
    final entryValues = _entryValues(entry);
    final missingFields = entryValues.entries
        .where((item) =>
            item.value.trim().isEmpty || item.value == 'MISSING')
        .map((item) => item.key)
        .toList(growable: false);
    if (missingFields.isNotEmpty) {
      return _failure(
        selectedEntryId,
        '所选词条缺少必要原文或来源字段（${missingFields.join('、')}）；未生成快照。',
      );
    }

    final result = AssistantToolResult(
      toolId: moduleId,
      title: '周公解梦',
      values: Map<String, String>.unmodifiable(entryValues),
      sourceIds: const [DreamToolExecutor.sourceId],
      arguments: Map<String, String>.unmodifiable({
        'entry_id': entry.id,
      }),
      disclaimer:
          '${kDreamDisclaimer} 吉凶标签和释义仅代表本地数据集中的传统民俗文本，不是事实判断或现实预测。数据集的来源字段仅作为原始元数据保留，不代表已完成历史文献版本鉴定。',
    );
    if (result.status != AssistantToolExecutionStatus.succeeded ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch({'entry_id': entry.id}).isNotEmpty ||
        result.sourceIds.length != 1 ||
        result.sourceIds.single != DreamToolExecutor.sourceId) {
      return _failure(selectedEntryId, '所选词条的结构、状态或本地来源校验失败。');
    }

    final values = <String, Object?>{
      for (final item in result.values.entries) item.key: item.value,
    };
    final baseSnapshot = <String, Object?>{
      'capabilityId': moduleId,
      'resultSchemaVersion': resultSchemaVersion,
      'ruleVersion': ruleVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': const [DreamToolExecutor.sourceId],
      'input': <String, Object?>{
        'method': 'explicitEntrySelection',
        'selectedEntryId': entry.id,
      },
      'result': <String, Object?>{
        'title': result.title,
        'values': values,
        'disclaimer': result.disclaimer,
      },
      'units': const <String, Object?>{},
      'missingFields': const <String>[],
      'displaySummary': '${entry.dream} · ${entry.category}/${entry.subcategory}',
      'provenance': const <String, Object?>{
        'dataset': DreamToolExecutor.sourceId,
        'selectionOwner': 'USER_EXPLICIT_SELECTION',
        'sourceFieldPolicy':
            'Preserve the dataset source field as metadata; do not assert historical edition authenticity.',
      },
      'privacy': const <String, Object?>{
        'freeTextDreamDescription': 'NOT_INCLUDED',
        'modelPromptPolicy': 'ONLY_EXPLAIN_EXPLICITLY_SELECTED_LOCAL_ENTRY',
      },
    };
    final snapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
    final snapshot = _deepUnmodifiable({
      ...baseSnapshot,
      'snapshotId': snapshotId,
    }) as Map<String, Object?>;

    return DreamResultContextExecution(
      result: result,
      structuredSnapshot: snapshot,
    );
  }

  static Map<String, String> _entryValues(DreamEntry entry) => {
        '词条 ID': entry.id,
        '分类': entry.category,
        '子分类': entry.subcategory,
        '关键词': entry.keyword,
        '梦境词条原文': entry.dream,
        '词条释义原文': entry.interpretation,
        '原始吉凶标签（民俗文本）': entry.auspicious,
        '词条来源字段': entry.source,
      };

  static DreamResultContextExecution _failure(
    String selectedEntryId,
    String reason,
  ) =>
      DreamResultContextExecution(
        result: AssistantToolResult(
          toolId: moduleId,
          title: '周公解梦',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': reason},
          arguments: Map<String, String>.unmodifiable({
            if (selectedEntryId.isNotEmpty) 'entry_id': selectedEntryId,
          }),
          disclaimer: '只有唯一且完整的本地词条才能建立情境上下文；本次未生成解释快照。',
        ),
      );

  static Object? _deepUnmodifiable(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final item in value.entries)
          item.key as String: _deepUnmodifiable(item.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
    }
    return value;
  }
}
