import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/in_memory_assistant_conversation_store.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/saved_chart_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/daily_almanac_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/almanac_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-almanac-context-',
    );
    DatabaseHelper.configureTestDatabase(
      'almanac_context_test.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('almanac snapshot binds the exact date, result fields and local sources', () {
    final snapshot = AlmanacToolExecutor.createStructuredSnapshot(
      DateTime(2026, 11, 18, 23, 45),
    );
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;

    expect(snapshot['capabilityId'], 'almanac');
    expect(snapshot['resultSchemaVersion'], AlmanacToolExecutor.resultSchemaVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input['date'], '2026-11-18');
    expect(snapshot['ruleVersion'], AlmanacToolExecutor.ruleVersion);
    expect(snapshot['sourceIds'], containsAll(AlmanacToolExecutor.resultSourceIds));
    expect(result['solarDate'], '2026-11-18');
    expect(result['ganzhi'], isA<Map<String, String>>());
    expect(result['yi'], isA<List<String>>());
    expect(result['ji'], isA<List<String>>());
    expect(result['festivals'], isA<Map<String, Object?>>());
    expect(
      (result['personalizedOverlay']! as Map<String, Object?>)['included'],
      isFalse,
      reason: '不得将最近保存命盘派生的本命生肖个人化提示混入黄历日期快照',
    );
    expect(snapshot['snapshotId'], hasLength(64));
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final differentDate =
        AlmanacToolExecutor.createStructuredSnapshot(DateTime(2026, 11, 19));
    expect(differentDate['snapshotId'], isNot(snapshot['snapshotId']));
  });

  test('almanac resolver rejects stale rules, altered anchors, unknown sources and title mismatch', () {
    final snapshot = AlmanacToolExecutor.createStructuredSnapshot(
      DateTime(2026, 11, 18),
    );
    final ref = AiContextResolver.buildAlmanacResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolved = AiContextResolver.resolveAlmanacToolResult(ref: ref);

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'almanac');
    expect(ref.sourceId, AlmanacToolExecutor.sourceId);
    expect(ref.snapshotId, snapshot['snapshotId']);
    expect(resolved.isResolved, isTrue);

    final prompt =
        AiContextPromptBuilder.buildAlmanacToolResult(resolvedResult: resolved.value!);
    expect(prompt, contains('2026-11-18'));
    expect(prompt, contains('民俗文化参考'));
    expect(prompt, contains('不得重新排盘、推算'));
    expect(prompt, contains('排除了页面可能展示的本命生肖个性化提示'));

    final staleRule = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'almanac-engine@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAlmanacToolResult(ref: staleRule).status,
      AiContextResolutionStatus.stale,
    );

    final changedDate = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId.replaceFirst('2026-11-18', '2026-11-19'),
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAlmanacToolResult(ref: changedDate).status,
      AiContextResolutionStatus.unknown,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:almanac',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAlmanacToolResult(ref: wrongSource).status,
      AiContextResolutionStatus.unknown,
    );

    final wrongTitle = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: '其他黄历',
    );
    expect(
      AiContextResolver.resolveAlmanacToolResult(ref: wrongTitle).status,
      AiContextResolutionStatus.unknown,
    );

    final malformedAnchor = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: 'almanac:result:unknown:date=2026-11-18',
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAlmanacToolResult(ref: malformedAnchor).status,
      AiContextResolutionStatus.unknown,
    );

    final tamperedSnapshot = Map<String, Object?>.from(snapshot);
    final tamperedResult = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    )..['yi'] = const ['被篡改的宜项'];
    tamperedSnapshot['result'] = tamperedResult;
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: ref,
        structuredSnapshot: tamperedSnapshot,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('daily almanac opens the contextual tools assistant with a verified snapshot', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
          ContextualAiConversationStoreScope(
        conversationStore: InMemoryAssistantConversationStore(),
        child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          extensions: [AppColors.light],
        ),
          home: const DailyAlmanacScreen(),
        ),
      ),
        );
    await tester.pumpAndSettle();

    // DailyAlmanacScreen reads the optional saved-chart zodiac overlay while
    // the contextual assistant initializes its SQLite conversation lookup.
    // Drain that first read outside fake-async before opening the assistant so
    // sqflite's transaction wait timer cannot be stranded at widget teardown.
    await tester.runAsync(() => SavedChartRepository.getAll());
    await tester.pump();

    expect(find.byType(DailyAlmanacScreen), findsOneWidget);
    final ask = find.byTooltip('问 AI 解读本日黄历');
    expect(ask, findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(ask);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final assistant = find.byType(LocalAiInterviewScreen);
    expect(assistant, findsOneWidget);
    final widget = tester.widget<LocalAiInterviewScreen>(assistant);
    expect(widget.initialMode, AssistantMode.tools);
    expect(widget.contextualExplanationOnly, isTrue);
    expect(widget.contextRef['kind'], 'toolResult');
    expect(widget.contextRef['moduleId'], 'almanac');
    expect(widget.contextRef['snapshotId'], hasLength(64));
    expect(widget.initialPrompt, contains('每日黄历结果'));
    expect(tester.takeException(), isNull);
  });
}
