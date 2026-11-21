import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/dream_data.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/dream_result_context_executor.dart';
import 'package:nihaisha_app/services/dream_tool_executor.dart';

void main() {
  const selectedId = 'action_001';

  test('只按用户明确选择的唯一 ID 建立词条情境快照', () {
    final entry = kDreamEntries.singleWhere((item) => item.id == selectedId);
    final execution = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedId,
    );

    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('dream'), isEmpty);
    expect(
      execution.result.validateArgumentsMatch({'entry_id': selectedId}),
      isEmpty,
    );
    expect(execution.result.sourceIds, [DreamToolExecutor.sourceId]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], DreamResultContextExecutor.moduleId);
    expect(
      snapshot['resultSchemaVersion'],
      DreamResultContextExecutor.resultSchemaVersion,
    );
    expect(snapshot['ruleVersion'], DreamResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input, {
      'method': 'explicitEntrySelection',
      'selectedEntryId': selectedId,
    });
    expect(values['词条 ID'], entry.id);
    expect(values['分类'], entry.category);
    expect(values['子分类'], entry.subcategory);
    expect(values['关键词'], entry.keyword);
    expect(values['梦境词条原文'], entry.dream);
    expect(values['词条释义原文'], entry.interpretation);
    expect(values['原始吉凶标签（民俗文本）'], entry.auspicious);
    expect(values['词条来源字段'], entry.source);
    expect(snapshot['sourceIds'], [DreamToolExecutor.sourceId]);
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );
  });

  test('重复建立相同词条快照得到稳定身份', () {
    final first = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedId,
    );
    final second = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedId,
    );

    expect(first.succeeded, isTrue);
    expect(second.succeeded, isTrue);
    expect(
      second.structuredSnapshot!['snapshotId'],
      first.structuredSnapshot!['snapshotId'],
    );
  });

  test('空 ID、不存在 ID 和带空白的 ID 均 fail closed', () {
    for (final id in ['', 'not-a-real-dream-entry', ' action_001 ']) {
      final execution = DreamResultContextExecutor.executeWithSnapshot(
        selectedEntryId: id,
      );
      expect(execution.succeeded, isFalse, reason: 'ID=$id');
      expect(execution.result.status.name, 'failed');
      expect(execution.structuredSnapshot, isNull);
      expect(execution.result.sourceIds, isEmpty);
    }
  });

  test('412 条数据的 ID 唯一且数据源版本固定在快照规则版本', () {
    final ids = kDreamEntries.map((entry) => entry.id).toList();
    expect(kDreamEntries, hasLength(412));
    expect(ids.toSet(), hasLength(ids.length));
    expect(
      DreamResultContextExecutor.ruleVersion,
      contains('dream-data-blob@ceaf925eb76f25c4df6488c0934520e4995fd409'),
    );
  });
}
