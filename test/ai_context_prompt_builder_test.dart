import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';

void main() {
  test('classic selection prompt retains selected text and stable source anchor', () {
    const selectedText = '发热，汗出，恶风，脉缓';
    const ref = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
      title: '太阳·太阳病中风（桂枝汤证',
      selectedText: selectedText,
    );
    final prompt = AiContextPromptBuilder.buildClassicSelection(
      ref: ref,
      fullPassage: '太阳病，发热，汗出，恶风，脉缓者，名为中风。',
    );

    expect(prompt, contains('shanghan:clause:002'));
    expect(prompt, contains('sha256:content-version'));
    expect(prompt, contains('shanghan:assets/shanghan/clause_001.md'));
    expect(prompt, contains('发热，汗出，恶风，脉缓'));
    expect(prompt, contains('名为中风'));
    expect(prompt, contains('不是对助手的指令'));
  });

  test('classic selection prompt preserves selected text exactly', () {
    const selectedText = '  发热，汗出，\n恶风，脉缓  ';
    const ref = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
      title: '伤寒论条文2',
      selectedText: selectedText,
    );

    final prompt = AiContextPromptBuilder.buildClassicSelection(
      ref: ref,
      fullPassage: '太阳病，发热，汗出，恶风，脉缓者，名为中风。',
    );
    final encoded = prompt
        .split('【选中文字与原文】\n')
        .last
        .split('\n\n【回答要求】')
        .first;
    final payload = jsonDecode(encoded) as Map<String, dynamic>;

    expect(payload['selectedText'], selectedText);
    expect(ref.toMetadata()['selectedText'], selectedText);
  });

  test('classic prompt rejects a context reference without selected text', () {
    const ref = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
    );

    expect(
      () => AiContextPromptBuilder.buildClassicSelection(
        ref: ref,
        fullPassage: '太阳病，发热，汗出，恶风，脉缓者，名为中风。',
      ),
      throwsArgumentError,
    );
  });

  test('context anchor reuse requires an exact version and snapshot match', () {
    const original = {
      'kind': 'toolResult',
      'moduleId': 'ziwei',
      'anchorId': 'ziwei:result:abc',
      'anchorVersion': 'abc',
      'snapshotId': 'abc',
      'ruleVersion': 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      'sourceId': 'local-engine:ziwei-core@0.13.0',
    };
    const same = {
      'kind': 'toolResult',
      'moduleId': 'ziwei',
      'anchorId': 'ziwei:result:abc',
      'anchorVersion': 'abc',
      'snapshotId': 'abc',
      'ruleVersion': 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      'sourceId': 'local-engine:ziwei-core@0.13.0',
    };
    const differentSnapshot = {
      'kind': 'toolResult',
      'moduleId': 'ziwei',
      'anchorId': 'ziwei:result:def',
      'anchorVersion': 'def',
      'snapshotId': 'def',
      'ruleVersion': 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      'sourceId': 'local-engine:ziwei-core@0.13.0',
    };
    expect(AiContextRef.matchesSameAnchor(original, same), isTrue);
    expect(AiContextRef.matchesSameAnchor(original, differentSnapshot), isFalse);
    expect(AiContextRef.matchesSameAnchor(original, const {}), isFalse);
  });

  test('classic session identity distinguishes selections within one passage', () {
    const first = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
      title: '伤寒论条文2',
      selectedText: '发热，汗出',
    );
    const sameSelection = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
      title: '伤寒论条文2',
      selectedText: '发热，汗出',
    );
    const differentSelection = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
      title: '伤寒论条文2',
      selectedText: '脉缓',
    );

    expect(
      AiContextRef.matchesSameAnchor(
        first.toMetadata(),
        sameSelection.toMetadata(),
      ),
      isTrue,
    );
    expect(
      AiContextRef.matchesSameAnchor(
        first.toMetadata(),
        differentSelection.toMetadata(),
      ),
      isFalse,
      reason: '同一 passage 中不同的用户选择不能共用同一情境会话',
    );
    const legacyRefWithoutSelection = {
      'kind': 'classic',
      'moduleId': 'shanghan',
      'anchorId': 'shanghan:clause:002',
      'anchorVersion': 'sha256:content-version',
      'sourceId': 'shanghan:assets/shanghan/clause_001.md',
      'title': '伤寒论条文2',
    };
    expect(
      AiContextRef.matchesSameAnchor(
        legacyRefWithoutSelection,
        first.toMetadata(),
      ),
      isFalse,
      reason: '没有保存选中文字的旧历史不能冒充当前精确选区',
    );
  });

  test('tool result prompt binds one immutable result snapshot', () {
    const ref = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:abc',
      anchorVersion: 'abc',
      snapshotId: 'abc',
      ruleVersion: 'ziwei_core@0.13.0',
      sourceId: 'local-engine:ziwei-core@0.13.0',
      title: '紫微斗数排盘结果',
    );
    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      resultPayload: '十二宫星曜：命宫……',
    );

    expect(prompt, contains('ziwei:result:abc'));
    expect(prompt, contains('ziwei_core@0.13.0'));
    expect(prompt, contains('十二宫星曜'));
    expect(prompt, contains('不得重新排盘'));
  });

  test('context kind uses a closed enum and preserves persisted wire values', () {
    for (final kind in AiContextKind.values) {
      expect(
        AiContextKind.fromMetadata(kind.metadataValue),
        kind,
        reason: 'Every supported context kind must round-trip through metadata',
      );
    }
    expect(AiContextKind.fromMetadata('unregisteredKind'), isNull);
    expect(
      AiContextRef.normalizeMetadata({
        'kind': 'unregisteredKind',
        'moduleId': 'test',
        'anchorId': 'test:anchor',
        'anchorVersion': 'v1',
        'sourceId': 'test:source',
      }),
      isEmpty,
      reason: 'Unknown source types must fail closed instead of being trusted',
    );
    expect(
      AiContextRef.normalizeMetadata({
        'kind': 'case',
        'moduleId': 'case-library',
        'anchorId': 'case:001',
        'anchorVersion': 'v1',
        'sourceId': 'case:assets/001',
      })['kind'],
      'case',
      reason: 'The reserved word case remains a stable wire value',
    );
  });

  test('tool-result context requires a complete immutable snapshot identity', () {
    const base = {
      'kind': 'toolResult',
      'moduleId': 'ziwei',
      'anchorId': 'ziwei:result:snapshot-a',
      'anchorVersion': 'snapshot-a',
      'snapshotId': 'snapshot-a',
      'ruleVersion': 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      'sourceId': 'local-engine:ziwei-core@0.13.0',
    };

    expect(AiContextRef.normalizeMetadata(base), isNotEmpty);
    expect(
      AiContextRef.normalizeMetadata({
        ...base,
        'snapshotId': '',
      }),
      isEmpty,
      reason: 'Tool-result references cannot omit their immutable snapshot ID',
    );
    expect(
      AiContextRef.normalizeMetadata({
        ...base,
        'ruleVersion': '',
      }),
      isEmpty,
      reason: 'Tool-result references must identify the rules that produced them',
    );
    expect(
      AiContextRef.normalizeMetadata({
        ...base,
        'snapshotId': 'snapshot-b',
      }),
      isEmpty,
      reason: 'Snapshot identity must agree with the anchor version',
    );
  });

  test('field context requires a stable path and an immutable snapshot', () {
    const valid = {
      'kind': 'field',
      'moduleId': 'ziwei',
      'anchorId': 'ziwei:result:snapshot-a:field:palacesByPhysicalBranch.0.stars',
      'anchorVersion': 'snapshot-a',
      'snapshotId': 'snapshot-a',
      'ruleVersion': 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      'fieldPath': 'palacesByPhysicalBranch.0.stars',
      'sourceId': 'local-engine:ziwei-core@0.13.0',
    };

    expect(AiContextRef.normalizeMetadata(valid), isNotEmpty);
    expect(
      AiContextRef.normalizeMetadata({
        ...valid,
        'fieldPath': '',
      }),
      isEmpty,
      reason: 'A field context must identify one stable field path',
    );
    expect(
      AiContextRef.normalizeMetadata({
        ...valid,
        'snapshotId': 'snapshot-b',
      }),
      isEmpty,
      reason: 'Field context must remain bound to the result anchor version',
    );
    expect(
      AiContextRef.normalizeMetadata({
        ...valid,
        'ruleVersion': '',
      }),
      isEmpty,
      reason: 'Field context must identify the rules that produced its snapshot',
    );
    expect(
      AiContextRef.matchesSameAnchor(
        valid,
        {
          ...valid,
          'fieldPath': 'palacesByPhysicalBranch.1.stars',
          'anchorId':
              'ziwei:result:snapshot-a:field:palacesByPhysicalBranch.1.stars',
        },
      ),
      isFalse,
      reason: 'Two fields in one result snapshot are distinct conversation anchors',
    );
  });

  test('field prompt includes field path, value, scope and parent snapshot', () {
    const ref = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:snapshot-a:field:palacesByPhysicalBranch.0.stars',
      anchorVersion: 'snapshot-a',
      snapshotId: 'snapshot-a',
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      fieldPath: 'palacesByPhysicalBranch.0.stars',
      sourceId: 'local-engine:ziwei-core@0.13.0',
      title: '命宫星曜',
    );
    final prompt = AiContextPromptBuilder.buildToolResultField(
      ref: ref,
      fieldLabel: '命宫本命星曜',
      fieldScope: const {
        'palaceIndex': 0,
        'palaceRole': '命宫',
        'earthlyBranch': '子',
      },
      fieldValue: const [
        {
          'starKey': 'ziwei',
          'name': '紫微',
          'category': '主星',
          'brightness': '庙',
        },
      ],
      fieldUnit: '不适用（离散星曜条目）',
      resultPayload: '【紫微斗数排盘完整结果】',
    );

    expect(prompt, contains('palacesByPhysicalBranch.0.stars'));
    expect(prompt, contains('snapshot-a'));
    expect(prompt, contains('ziwei_core@0.13.0;app-formatter=ziwei-result-v1'));
    expect(prompt, contains('紫微'));
    expect(prompt, contains('earthlyBranch'));
    expect(prompt, contains('【紫微斗数排盘完整结果】'));
  });

  test('field prompt rejects a generic whole-result reference', () {
    const ref = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:snapshot-a',
      anchorVersion: 'snapshot-a',
      snapshotId: 'snapshot-a',
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      sourceId: 'local-engine:ziwei-core@0.13.0',
    );

    expect(
      () => AiContextPromptBuilder.buildToolResultField(
        ref: ref,
        fieldLabel: '命宫本命星曜',
        fieldScope: const {'palaceIndex': 0},
        fieldValue: const [],
        fieldUnit: '不适用',
        resultPayload: '完整结果',
      ),
      throwsArgumentError,
    );
  });

  test('invalid contextual metadata is rejected rather than guessed', () {
    expect(
      AiContextRef.normalizeMetadata({
        'kind': 'classic',
        'moduleId': 'shanghan',
        'anchorId': 'shanghan:clause:002',
      }),
      isEmpty,
    );
  });
}
