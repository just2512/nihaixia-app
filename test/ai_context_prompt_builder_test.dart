import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziwei_core/ziwei_core.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/assistant_chart_result_formatter.dart';
import 'package:nihaisha_app/services/ziwei_engine.dart';

Map<String, Object?> _buildStructuredZiweiSnapshot(ZiweiChart chart) {
  final base = buildZiweiStructuredResultForAssistant(
    solar: DateTime(2000, 8, 16, 10),
    useTrueSolarTime: true,
    distinguishZiShi: false,
    locationDescription: '上海',
    longitude: 121.47,
    latitude: 31.23,
    chart: chart,
  );
  final snapshotId =
      AiToolResultSnapshot.createStructuredId(snapshot: base);
  return Map<String, Object?>.unmodifiable({
    ...base,
    'snapshotId': snapshotId,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formula knowledge entry prompt separates context sections with real newlines', () async {
    await FormulaRepository.load();
    expect(FormulaRepository.getAll(), isNotEmpty);
    final formula = FormulaRepository.getAll().first;
    final ref = AiContextResolver.buildFormulaContextRef(formula);
    final resolution = AiContextResolver.resolveFormula(ref: ref);
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildKnowledgeEntry(
      entry: resolution.value!,
    );
    expect(
      prompt,
      contains('【当前知识条目情境】\n知识模块：'),
    );
    expect(
      prompt,
      contains('\n【App 实际知识条目】\n'),
    );
    expect(
      prompt,
      contains('\n【回答要求】\n'),
    );
  });



  test('knowledge entry intent is short and adds analysis value rather than repeating source data', () async {
    await FormulaRepository.load();
    final formula = FormulaRepository.getAll().first;
    final ref = AiContextResolver.buildFormulaContextRef(formula);
    final resolution = AiContextResolver.resolveFormula(ref: ref);
    expect(resolution.isResolved, isTrue);

    final entry = resolution.value!;
    final intent = AiContextPromptBuilder.buildKnowledgeEntryInterpretationIntent(
      entry: entry,
    );
    final modelContext = AiContextPromptBuilder.buildKnowledgeEntryModelContext(
      entry: entry,
    );

    expect(intent, contains('整体组方结构'));
    expect(intent, contains('配伍逻辑'));
    expect(intent, isNot(contains('sourceId')));
    expect(intent, isNot(contains('anchorVersion')));
    expect(intent, isNot(contains('"components"')));
    expect(intent.length, lessThan(120));

    expect(modelContext, contains('不要逐项复述字段'));
    expect(modelContext, contains('条目明确记载'));
    expect(modelContext, contains('基于条目内容的归纳'));
    expect(modelContext, contains('MISSING 或 UNKNOWN'));
    expect(modelContext, contains(formula.name));
    expect(modelContext, contains('components'));
    expect(modelContext, isNot(contains('"id"')));
    expect(modelContext, isNot(contains(entry.ref.sourceId)));
    expect(modelContext, isNot(contains(entry.ref.anchorVersion)));
  });

  test('contextual acupuncture model input omits App-owned source and snapshot identifiers', () async {
    await AcupunctureRepository.load();
    final category = AcupunctureRepository.getAll().singleWhere(
      (item) => item.id == '01',
    );
    final entry = category.entries.singleWhere((item) => item.id == 1);
    final ref = AiContextResolver.buildAcupunctureEntryContextRef(
      categoryId: category.id,
      entry: entry,
    );
    final resolution = AiContextResolver.resolveAcupunctureEntry(ref: ref);
    expect(resolution.isResolved, isTrue);

    final modelContext = AiContextPromptBuilder.buildKnowledgeEntryModelContext(
      entry: resolution.value!,
    );

    expect(modelContext, contains('冠心病'));
    expect(modelContext, contains('关元'));
    expect(modelContext, isNot(contains(ref.sourceId)));
    expect(modelContext, isNot(contains(ref.snapshotId!)));
    expect(modelContext, isNot(contains(ref.ruleVersion!)));
    for (final internalField in [
      'sourceId',
      'sourceIds',
      'snapshotId',
      'ruleVersion',
      'capabilityId',
      'resultSchemaVersion',
      'categoryId',
      'entryId',
      'localBacklink',
    ]) {
      expect(modelContext, isNot(contains(internalField)));
    }
    // The original source marker is part of the actual prescription record,
    // not an App locator, and remains available for careful interpretation.
    expect(modelContext, contains(entry.source));
  });

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

  test('tool result prompt sends a verified complete structured snapshot', () {
    final chart = calculateZiweiChart(
      solar: DateTime(2000, 8, 16, 10),
      gender: Gender.male,
      location: Location(121.47, 31.23),
      useTrueSolarTime: true,
    );
    final snapshot = _buildStructuredZiweiSnapshot(chart);
    final snapshotId = snapshot['snapshotId']! as String;
    final ruleVersion = snapshot['ruleVersion']! as String;
    final ref = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      sourceId: 'local-engine:ziwei-core@0.13.0',
      title: '紫微斗数排盘结果',
    );
    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    const structuredMarker = '【App 实际计算结果（结构化快照）】\n';
    final structuredStart =
        prompt.indexOf(structuredMarker) + structuredMarker.length;
    final structuredEnd = prompt.indexOf('\n\n【回答要求】', structuredStart);
    final structured = jsonDecode(
      prompt.substring(structuredStart, structuredEnd),
    ) as Map<String, dynamic>;
    expect(prompt, contains('ziwei:result:$snapshotId'));
    expect(prompt, contains(ruleVersion));
    expect(prompt, contains('palacesByPhysicalBranch'));
    expect(prompt, contains('interpretationTemplates'));
    expect(prompt, contains('不得重新排盘'));
    expect(
      (snapshot['result']! as Map)['palacesByPhysicalBranch'],
      hasLength(12),
    );
    expect(structured, isA<Map<String, dynamic>>());
    expect(structured['capabilityId'], 'ziwei');
    expect(structured['executionStatus'], 'SUCCESS');
    expect(
      structured['sourceIds'],
      contains('local-engine:ziwei-core@0.13.0'),
    );
    expect(structured['resultSchemaVersion'], 'ziwei-structured-result-v1');
    expect(
      (structured['input'] as Map)['location'],
      containsPair('longitude', 121.47),
    );
    expect(
      (structured['result'] as Map)['palacesByPhysicalBranch'],
      hasLength(12),
    );
    final structuredResult = structured['result'] as Map;
    expect(structuredResult['bazi'], isA<Map>());
    expect(structuredResult['lunar'], isA<Map>());
    expect(structuredResult['elementBureau'], isNotNull);
    expect(structuredResult['lifePalace'], isA<Map>());
    expect(structuredResult['bodyPalace'], isA<Map>());
    expect(structuredResult['sihua'], isA<List>());
    expect(structuredResult['decades'], isA<List>());
    expect(structuredResult['decades'], isNotEmpty);
    expect(structuredResult['selectedFlow'], isA<Map>());
    expect(
      structuredResult['interpretationTemplates'],
      isA<Map>(),
    );
    expect(structured['units'], isA<Map>());
    expect(structured['missingFields'], isA<List>());
    expect(structured['displaySummary'], isA<String>());
  });

  test('tool result prompt rejects a tampered structured result', () {
    final chart = calculateZiweiChart(
      solar: DateTime(2000, 8, 16, 10),
      gender: Gender.male,
      location: Location(121.47, 31.23),
      useTrueSolarTime: true,
    );
    final snapshot = _buildStructuredZiweiSnapshot(chart);
    final snapshotId = snapshot['snapshotId']! as String;
    final ref = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: snapshot['ruleVersion']! as String,
      sourceId: 'local-engine:ziwei-core@0.13.0',
      title: '紫微斗数排盘结果',
    );
    final result = Map<String, Object?>.from(snapshot['result']! as Map);
    result['elementBureau'] = 'tampered';
    final tampered = {...snapshot, 'result': result};
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: tampered),
      isNot(snapshotId),
      reason: 'Any mutation inside the structured result must change its snapshot digest',
    );

    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: ref,
        structuredSnapshot: tampered,
      ),
      throwsArgumentError,
    );

    final alteredUnits = {
      ...snapshot,
      'units': {
        ...Map<String, Object?>.from(snapshot['units']! as Map),
        'result.decades.startAge': 'tampered-unit',
      },
    };
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: ref,
        structuredSnapshot: alteredUnits,
      ),
      throwsArgumentError,
      reason: 'Units and measurement semantics are part of snapshot identity',
    );

    final alteredProvenance = {
      ...snapshot,
      'sourceIds': const ['unverified:source'],
    };
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: ref,
        structuredSnapshot: alteredProvenance,
      ),
      throwsArgumentError,
      reason: 'Source provenance is part of snapshot identity',
    );

    final alteredMissingFields = {
      ...snapshot,
      'missingFields': const ['tampered.field'],
    };
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: ref,
        structuredSnapshot: alteredMissingFields,
      ),
      throwsArgumentError,
      reason: 'Missing-field declarations are part of snapshot identity',
    );
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
    expect(
      AiContextRef.normalizeMetadata({
        'kind': 'knowledgeEntry',
        'moduleId': 'meridian',
        'anchorId': 'meridian:detail:少阳',
        'anchorVersion': 'snapshot-v1',
        'sourceId': 'local-data:diagnostic-rules:meridianDetails',
      }),
      isEmpty,
      reason: 'Knowledge entry references must carry an immutable content snapshot identity',
    );
    expect(
      AiContextRef.normalizeMetadata({
        'kind': 'knowledgeEntry',
        'moduleId': 'meridian',
        'anchorId': 'meridian:detail:少阳',
        'anchorVersion': 'snapshot-v1',
        'snapshotId': 'snapshot-v1',
        'ruleVersion': 'diagnostic-rules-meridian-details-v1',
        'sourceId': 'local-data:diagnostic-rules:meridianDetails',
      })['kind'],
      'knowledgeEntry',
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

  test('field prompt is built only from a resolved structured engine field', () {
    final chart = calculateZiweiChart(
      solar: DateTime(2000, 8, 16, 10),
      gender: Gender.male,
      location: Location(121.47, 31.23),
      useTrueSolarTime: true,
    );
    final snapshot = _buildStructuredZiweiSnapshot(chart);
    final snapshotId = snapshot['snapshotId']! as String;
    final ruleVersion = snapshot['ruleVersion']! as String;
    const fieldPath = 'palacesByPhysicalBranch.0.stars';
    final ref = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId:field:$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      fieldPath: fieldPath,
      sourceId: 'local-engine:ziwei-core@0.13.0',
      title: '宫位星曜',
    );
    final resolution = AiContextResolver.resolveZiweiPalaceStars(
      ref: ref,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: snapshot,
    );

    expect(resolution.status, AiContextResolutionStatus.resolved);
    expect(resolution.isResolved, isTrue);
    final prompt = AiContextPromptBuilder.buildToolResultField(
      resolvedField: resolution.value!,
    );

    expect(prompt, contains(fieldPath));
    expect(prompt, contains(snapshotId));
    expect(prompt, contains(ruleVersion));
    expect(prompt, contains('fieldValue'));
    expect(prompt, contains('starKey'));
    expect(prompt, contains('palaceIndex'));
    expect(prompt, contains('fullStructuredSnapshot'));
    expect(prompt, contains('interpretationTemplates'));
  });

  test('field resolver rejects a generic whole-result reference', () {
    final chart = calculateZiweiChart(
      solar: DateTime(2000, 8, 16, 10),
      gender: Gender.male,
      location: Location(121.47, 31.23),
      useTrueSolarTime: true,
    );
    final snapshot = _buildStructuredZiweiSnapshot(chart);
    final snapshotId = snapshot['snapshotId']! as String;
    final ruleVersion = snapshot['ruleVersion']! as String;
    final ref = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      sourceId: 'local-engine:ziwei-core@0.13.0',
    );
    final resolution = AiContextResolver.resolveZiweiPalaceStars(
      ref: ref,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: snapshot,
    );

    expect(resolution.status, AiContextResolutionStatus.unknown);
    expect(resolution.value, isNull);
  });

  test('field resolver refuses stale snapshots, modified data and missing paths', () {
    final chart = calculateZiweiChart(
      solar: DateTime(2000, 8, 16, 10),
      gender: Gender.male,
      location: Location(121.47, 31.23),
      useTrueSolarTime: true,
    );
    final snapshot = _buildStructuredZiweiSnapshot(chart);
    final snapshotId = snapshot['snapshotId']! as String;
    final ruleVersion = snapshot['ruleVersion']! as String;
    const fieldPath = 'palacesByPhysicalBranch.0.stars';
    final ref = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId:field:$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      fieldPath: fieldPath,
      sourceId: 'local-engine:ziwei-core@0.13.0',
    );

    final stale = AiContextResolver.resolveZiweiPalaceStars(
      ref: ref,
      chart: chart,
      expectedSnapshotId: 'snapshot-other',
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: snapshot,
    );
    expect(stale.status, AiContextResolutionStatus.stale);

    const missingPath = 'palacesByPhysicalBranch.99.stars';
    final missingRef = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId:field:$missingPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      fieldPath: missingPath,
      sourceId: 'local-engine:ziwei-core@0.13.0',
    );
    final missing = AiContextResolver.resolveZiweiPalaceStars(
      ref: missingRef,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: snapshot,
    );
    expect(missing.status, AiContextResolutionStatus.missing);
    expect(missing.value, isNull);

    const unsupportedPath = 'palacesByPhysicalBranch.0.ganzhi';
    final unsupportedRef = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId:field:$unsupportedPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      fieldPath: unsupportedPath,
      sourceId: 'local-engine:ziwei-core@0.13.0',
    );
    final unsupported = AiContextResolver.resolveZiweiPalaceStars(
      ref: unsupportedRef,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: snapshot,
    );
    expect(unsupported.status, AiContextResolutionStatus.unknown);

    final foreignSourceRef = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$snapshotId:field:$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion,
      fieldPath: fieldPath,
      sourceId: 'unverified:source',
    );
    final foreignSource = AiContextResolver.resolveZiweiPalaceStars(
      ref: foreignSourceRef,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: snapshot,
    );
    expect(foreignSource.status, AiContextResolutionStatus.unknown);
    expect(foreignSource.value, isNull);

    final result = Map<String, Object?>.from(snapshot['result']! as Map);
    result['elementBureau'] = 'tampered';
    final tampered = {...snapshot, 'result': result};
    final modified = AiContextResolver.resolveZiweiPalaceStars(
      ref: ref,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: tampered,
    );
    expect(modified.status, AiContextResolutionStatus.stale);
    expect(modified.value, isNull);

    // Recompute a valid digest after altering only the palace role metadata.
    // The resolver must still compare that field scope with the live engine
    // result rather than trusting a self-consistent but semantically foreign
    // snapshot.
    final scopeAlteredResult =
        Map<String, Object?>.from(snapshot['result']! as Map);
    final originalPalaces =
        scopeAlteredResult['palacesByPhysicalBranch']! as List;
    final alteredPalaces = originalPalaces
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
    alteredPalaces[0]['roleLabel'] = '迁移宫';
    scopeAlteredResult['palacesByPhysicalBranch'] = alteredPalaces;
    final scopeAlteredBase = {
      ...snapshot,
      'result': scopeAlteredResult,
    };
    final scopeAlteredId = AiToolResultSnapshot.createStructuredId(
      snapshot: scopeAlteredBase,
    );
    final scopeAlteredSnapshot = {
      ...scopeAlteredBase,
      'snapshotId': scopeAlteredId,
    };
    final scopeAlteredRef = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:$scopeAlteredId:field:$fieldPath',
      anchorVersion: scopeAlteredId,
      snapshotId: scopeAlteredId,
      ruleVersion: ruleVersion,
      fieldPath: fieldPath,
      sourceId: 'local-engine:ziwei-core@0.13.0',
    );
    final scopeAltered = AiContextResolver.resolveZiweiPalaceStars(
      ref: scopeAlteredRef,
      chart: chart,
      expectedSnapshotId: scopeAlteredId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: scopeAlteredSnapshot,
    );
    expect(scopeAltered.status, AiContextResolutionStatus.stale);
    expect(scopeAltered.value, isNull);

    final failedExecution = {
      ...snapshot,
      'executionStatus': 'FAILED',
    };
    final failed = AiContextResolver.resolveZiweiPalaceStars(
      ref: ref,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: failedExecution,
    );
    expect(failed.status, AiContextResolutionStatus.unknown);
    expect(failed.value, isNull);

    final unsupportedSchema = {
      ...snapshot,
      'resultSchemaVersion': 'unregistered-schema',
    };
    final unknownSchema = AiContextResolver.resolveZiweiPalaceStars(
      ref: ref,
      chart: chart,
      expectedSnapshotId: snapshotId,
      expectedRuleVersion: ruleVersion,
      structuredSnapshot: unsupportedSchema,
    );
    expect(unknownSchema.status, AiContextResolutionStatus.unknown);
    expect(unknownSchema.value, isNull);
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
