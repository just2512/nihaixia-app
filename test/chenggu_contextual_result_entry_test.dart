import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/chenggu_data.dart';
import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/chenggu_result_context_executor.dart';
import 'package:nihaisha_app/services/chenggu_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const arguments = {'birth_date': '1990-01-02', 'birth_time': '08:30'};

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = SettingsRepository.instance;
    if (!settings.isLoaded) await settings.load();
    await ChengguData.ensureLoaded();
  });

  test('称骨结果生成稳定快照并绑定引擎、数据和设置来源', () async {
    final execution = await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('chenggu'), isEmpty);
    expect(execution.result.validateArgumentsMatch(arguments), isEmpty);
    expect(execution.result.sourceIds, [ChengguToolExecutor.sourceId, ChengguToolExecutor.dataSourceId]);
    final snapshot = execution.structuredSnapshot!;
    expect(snapshot['capabilityId'], 'chenggu');
    expect(snapshot['resultSchemaVersion'], ChengguResultContextExecutor.resultSchemaVersion);
    expect(snapshot['ruleVersion'], ChengguResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(AiToolResultSnapshot.createStructuredId(snapshot: snapshot), snapshot['snapshotId']);
    final repeated = await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    expect(repeated.structuredSnapshot!['snapshotId'], snapshot['snapshotId']);
  });

  test('Resolver 重建结果；Prompt 脱敏精确出生日期和钟点', () async {
    final execution = await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildChengguResultContextRef(structuredSnapshot: snapshot);
    final resolution = await AiContextResolver.resolveChengguToolResult(ref: ref, structuredSnapshot: snapshot);
    expect(resolution.isResolved, isTrue);
    final prompt = AiContextPromptBuilder.buildToolResult(ref: ref, structuredSnapshot: resolution.value!.structuredSnapshot);
    expect(prompt, contains('REDACTED_LOCAL_ONLY'));
    expect(prompt, contains('传统民俗文化文本'));
    expect(prompt, isNot(contains('1990-01-02')));
    expect(prompt, isNot(contains('08:30')));
  });

  test('Resolver 拒绝错源、过期规则和篡改快照', () async {
    final execution = await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildChengguResultContextRef(structuredSnapshot: snapshot);
    final wrongSource = AiContextRef(kind: AiContextKind.toolResult, moduleId: ref.moduleId,
      anchorId: ref.anchorId, anchorVersion: ref.anchorVersion, snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion, sourceId: 'unverified:chenggu', title: ref.title);
    expect((await AiContextResolver.resolveChengguToolResult(ref: wrongSource, structuredSnapshot: snapshot)).status,
      AiContextResolutionStatus.unknown);
    final stale = AiContextRef(kind: AiContextKind.toolResult, moduleId: ref.moduleId,
      anchorId: ref.anchorId, anchorVersion: ref.anchorVersion, snapshotId: ref.snapshotId,
      ruleVersion: 'chenggu@STALE', sourceId: ref.sourceId, title: ref.title);
    expect((await AiContextResolver.resolveChengguToolResult(ref: stale, structuredSnapshot: snapshot)).status,
      AiContextResolutionStatus.stale);
    final changedResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final changedValues = Map<String, Object?>.from(changedResult['values']! as Map);
    changedValues['称骨歌诀'] = '伪造内容';
    changedResult['values'] = changedValues;
    final tampered = {...snapshot, 'result': changedResult};
    expect((await AiContextResolver.resolveChengguToolResult(ref: ref, structuredSnapshot: tampered)).status,
      AiContextResolutionStatus.stale);
    expect(() => AiContextPromptBuilder.buildToolResult(ref: ref, structuredSnapshot: tampered), throwsArgumentError);
  });

  test('缺参、非法输入和额外字段不会生成上下文快照', () async {
    for (final invalid in [
      const {'birth_date': '1990-01-02'},
      const {'birth_date': '1990-02-30', 'birth_time': '08:30'},
      const {'birth_date': '1990-01-02', 'birth_time': '25:90'},
      const {'birth_date': '1990-01-02', 'birth_time': '08:30', 'extra': 'x'},
    ]) {
      final result = await ChengguResultContextExecutor.executeWithSnapshot(invalid);
      expect(result.succeeded, isFalse);
      expect(result.structuredSnapshot, isNull);
    }
  });
}
