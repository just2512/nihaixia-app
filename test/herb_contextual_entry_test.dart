import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/herb_detail_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/in_memory_assistant_conversation_store.dart';
import 'support/in_memory_assistant_conversation_store.dart';


var _databaseSequence = 0;


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await HerbRepository.load();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'herb_contextual_entry_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  test('herb context resolves only against the verified exact asset entry', () {
    final herb = HerbRepository.getAll().first;
    final ref = AiContextResolver.buildHerbContextRef(herb);
    final resolved = AiContextResolver.resolveHerb(ref: ref);

    expect(ref.kind, AiContextKind.herb);
    expect(ref.moduleId, 'herb');
    expect(ref.sourceId, 'assets/data/herbs.json#${herb.name}');
    expect(ref.anchorId, 'herb:${herb.name}');
    expect(resolved.isResolved, isTrue);
    expect(resolved.value?.content['name'], herb.name);

    final prompt = AiContextPromptBuilder.buildHerbKnowledgeEntry(
      entry: resolved.value!,
    );
    expect(prompt, contains(herb.name));
    expect(prompt, contains('herbs.json'));
    expect(prompt, contains('本经原文'));
    expect(prompt, contains('不得补造剂量'));

    final staleRef = AiContextRef(
      kind: AiContextKind.herb,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: 'assets/data/herbs.json@STALE',
      sourceId: ref.sourceId,
      title: herb.name,
    );
    expect(
      AiContextResolver.resolveHerb(ref: staleRef).status,
      AiContextResolutionStatus.unknown,
    );

    final foreignSource = AiContextRef(
      kind: AiContextKind.herb,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      sourceId: 'unverified:herb',
      title: herb.name,
    );
    expect(
      AiContextResolver.resolveHerb(ref: foreignSource).status,
      AiContextResolutionStatus.unknown,
    );

    final missing = AiContextRef(
      kind: AiContextKind.herb,
      moduleId: ref.moduleId,
      anchorId: 'herb:不存在的药材',
      anchorVersion: ref.anchorVersion,
      sourceId: 'assets/data/herbs.json#不存在的药材',
      title: '不存在的药材',
    );
    expect(
      AiContextResolver.resolveHerb(ref: missing).status,
      AiContextResolutionStatus.missing,
    );
  });

  testWidgets(
    'herb detail exposes a contextual Ask AI entry without opening it automatically',
    (tester) async {
      final herb = HerbRepository.getAll().first;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(775, 900);
      tester.view.displayFeatures = const <DisplayFeature>[];

      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(Brightness.light),
              extensions: [AppColors.light],
            ),
            home: HerbDetailScreen(herb: herb),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HerbDetailScreen), findsOneWidget);
      expect(find.text('问 AI 解读当前本草'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      final ask = find.text('问 AI 解读当前本草');
      await tester.ensureVisible(ask);
      await tester.pumpAndSettle();
      await tester.tap(ask);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final widget = tester.widget<LocalAiInterviewScreen>(assistant);
      expect(widget.initialMode, AssistantMode.learning);
      expect(widget.contextualExplanationOnly, isTrue);
      expect(widget.contextRef['kind'], 'herb');
      expect(widget.contextRef['moduleId'], 'herb');
      expect(widget.contextRef['anchorId'], 'herb:${herb.name}');
      expect(widget.contextRef['sourceId'],
          'assets/data/herbs.json#${herb.name}');
      expect(widget.initialPrompt, contains(herb.name));
      expect(widget.initialPrompt, contains('不得补造剂量'));
      expect(tester.takeException(), isNull);

    },
  );
}
