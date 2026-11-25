import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/acupuncture_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var databaseSequence = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AcupunctureRepository.load();
    await AcupointRepository.load();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'acupuncture_contextual_entry_\${databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  testWidgets(
    'acupuncture prescription entry starts a concise one-tap contextual interpretation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(775, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(Brightness.light),
              extensions: [AppColors.light],
            ),
            home: const Scaffold(body: AcupunctureScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final ask = find.text('问 AI 解读当前处方条目').first;
      expect(ask, findsOneWidget);
      await tester.ensureVisible(ask);
      await tester.pump();
      await tester.tap(ask);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistantFinder = find.byType(LocalAiInterviewScreen);
      expect(assistantFinder, findsOneWidget);
      final assistant =
          tester.widget<LocalAiInterviewScreen>(assistantFinder);
      expect(assistant.initialMode, AssistantMode.learning);
      expect(assistant.contextualExplanationOnly, isTrue);
      expect(assistant.contextRef['kind'], 'knowledgeEntry');
      expect(assistant.contextRef['moduleId'], 'acupuncture-prescriptions');
      expect(assistant.contextRef['anchorId'], startsWith('acupuncture-prescriptions:'));
      expect(assistant.initialPrompt, isNull);
      expect(assistant.initialUserMessage, contains('当前针灸条目'));
      expect(assistant.initialUserMessage, isNot(contains('acupuncture:')));
      expect(assistant.autoSendInitialMessage, isTrue);
      expect(assistant.resolveContextualKnowledgeEntry, isTrue);
      expect(tester.takeException(), isNull);

      Navigator.of(
        tester.element(assistantFinder),
        rootNavigator: true,
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
  );
}
