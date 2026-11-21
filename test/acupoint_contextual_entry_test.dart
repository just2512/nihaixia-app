import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/zhenjiu_lecture_index.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/acupoint_detail_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

var _databaseSequence = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AcupointRepository.load();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'acupoint_contextual_entry_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  test('acupoint context resolves only one exact source-bound local record', () {
    final point = AcupointRepository.getAll().singleWhere(
      (item) => item.name == '内关穴',
    );
    final ref = AiContextResolver.buildAcupointContextRef(acupoint: point);
    final resolution = AiContextResolver.resolveAcupoint(ref: ref);

    expect(ref.kind, AiContextKind.knowledgeEntry);
    expect(ref.moduleId, 'acupoint');
    expect(ref.anchorId, 'acupoint:内关穴');
    expect(ref.snapshotId, hasLength(64));
    expect(ref.anchorVersion, ref.snapshotId);
    expect(ref.ruleVersion, AiContextResolver.acupointAssetVersion);
    expect(
      ref.sourceId,
      'assets/data/acupoints.json#内关穴',
    );
    expect(resolution.isResolved, isTrue);
    expect(resolution.value?.title, point.name);
    final record = resolution.value!.content['entry']! as Map;
    expect(record['name'], point.name);
    expect(record['meridian'], point.meridian);
    expect(record['location'], point.location);
    expect(record['needling'], point.needling);

    final prompt = AiContextPromptBuilder.buildAcupointKnowledgeEntry(
      entry: resolution.value!,
    );
    expect(prompt, contains('内关穴'));
    expect(prompt, contains('acupoints.json'));
    expect(prompt, contains('token 计数：UNKNOWN'));
    expect(prompt, contains('不得根据穴位名称'));
    expect(prompt, contains('不得扩展成针对个人'));
    expect(prompt, contains('不得补造'));

    final staleVersion = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'assets/data/acupoints.json@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupoint(ref: staleVersion).status,
      AiContextResolutionStatus.stale,
    );

    final wrongSource = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:acupoint',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupoint(ref: wrongSource).status,
      AiContextResolutionStatus.unknown,
    );

    final wrongTitle = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: '足三里穴',
    );
    expect(
      AiContextResolver.resolveAcupoint(ref: wrongTitle).status,
      AiContextResolutionStatus.unknown,
    );

    const alteredDigest =
        '0000000000000000000000000000000000000000000000000000000000000000';
    final alteredSnapshot = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: alteredDigest,
      snapshotId: alteredDigest,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupoint(ref: alteredSnapshot).status,
      AiContextResolutionStatus.stale,
    );

    final missing = AiContextRef(
      kind: AiContextKind.knowledgeEntry,
      moduleId: 'acupoint',
      anchorId: 'acupoint:不存在的穴位',
      anchorVersion: alteredDigest,
      snapshotId: alteredDigest,
      ruleVersion: AiContextResolver.acupointAssetVersion,
      sourceId: 'assets/data/acupoints.json#不存在的穴位',
      title: '不存在的穴位',
    );
    expect(
      AiContextResolver.resolveAcupoint(ref: missing).status,
      AiContextResolutionStatus.missing,
    );
  });

  testWidgets(
    'acupoint detail opens a knowledge-anchored learning assistant at 402 and 775dp',
    (tester) async {
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await ZhenJiuLectureIndex.load();
      });

      final point = AcupointRepository.getAll().singleWhere(
        (item) => item.name == '内关穴',
      );
      for (final width in [402.0, 775.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 2400);
        await tester.pumpWidget(
          ContextualAiConversationStoreScope(
            conversationStore: InMemoryAssistantConversationStore(),
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: AppColors.colorSchemeFor(Brightness.light),
                extensions: [AppColors.light],
              ),
              home: AcupointDetailScreen(acupoint: point),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(AcupointDetailScreen), findsOneWidget);
        expect(find.text('问 AI 解读当前穴位'), findsOneWidget);
        expect(find.byKey(const ValueKey('acupoint-contextual-ask')), findsOneWidget);
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);

        final pageList = tester.widget<ListView>(
          find.byKey(const ValueKey('acupoint-detail-scroll')),
        );
        final pageController = pageList.controller!;
        await tester.drag(
          find.byKey(const ValueKey('acupoint-detail-scroll')),
          const Offset(0, -360),
        );
        await tester.pumpAndSettle();
        final beforeOpen = pageController.position.pixels;
        expect(beforeOpen, greaterThan(0));

        await tester.tap(find.byKey(const ValueKey('acupoint-contextual-ask')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistantFinder = find.byType(LocalAiInterviewScreen);
        expect(assistantFinder, findsOneWidget);
        final assistant =
            tester.widget<LocalAiInterviewScreen>(assistantFinder);
        expect(assistant.initialMode, AssistantMode.learning);
        expect(assistant.contextualExplanationOnly, isTrue);
        expect(assistant.contextRef['kind'], 'knowledgeEntry');
        expect(assistant.contextRef['moduleId'], 'acupoint');
        expect(assistant.contextRef['anchorId'], 'acupoint:内关穴');
        expect(assistant.contextRef['snapshotId'], hasLength(64));
        expect(
          assistant.contextRef['sourceId'],
          'assets/data/acupoints.json#内关穴',
        );
        expect(assistant.initialPrompt, contains('内关穴'));
        expect(assistant.initialPrompt, contains('不得提供'));
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistantFinder),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(find.byType(AcupointDetailScreen), findsOneWidget);
        expect(pageController.position.pixels, closeTo(beforeOpen, 0.5));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
