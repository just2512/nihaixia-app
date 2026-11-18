import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/in_memory_assistant_conversation_store.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/engine/yijing_engine.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/yijing_result_screen.dart';
import 'package:nihaisha_app/screens/yijing_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/yijing_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-yijing-context-',
    );
    DatabaseHelper.configureTestDatabase(
      'yijing_context_test.db',
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

  test('all four YiJing methods produce immutable full result snapshots', () {
    final inputs = <Map<String, String>>[
      const {'method': 'number', 'first': '3', 'second': '7'},
      YiJingToolExecutor.prepareExecutionArguments(
        const {'method': 'time'},
        now: DateTime(2026, 11, 18, 9, 42),
      ),
      const {
        'method': 'manual',
        'upper': '1',
        'lower': '8',
        'moving': '2',
      },
      YiJingToolExecutor.prepareExecutionArguments(
        const {'method': 'coins'},
        rng: Random(41),
      ),
    ];

    for (final input in inputs) {
      final snapshot = YiJingToolExecutor.createStructuredSnapshot(input);
      final result = snapshot['result']! as Map<String, Object?>;
      final primary = result['primary']! as Map<String, Object?>;
      final recordedInput = snapshot['input']! as Map<String, Object?>;
      expect(snapshot['capabilityId'], 'yijing');
      expect(snapshot['executionStatus'], 'SUCCESS');
      expect(snapshot['sourceIds'], containsAll([
        YiJingToolExecutor.sourceId,
        YiJingToolExecutor.dataSourceId,
      ]));
      expect(snapshot['ruleVersion'], YiJingToolExecutor.ruleVersion);
      expect(snapshot['snapshotId'], hasLength(64));
      expect(primary['seq'], inInclusiveRange(1, 64));
      expect(primary['lines'], hasLength(6));
      expect(result['primaryLines'], hasLength(6));
      expect(result['movingTitles'], isA<List<String>>());
      expect(result['movingTexts'], isA<List<String>>());
      expect(recordedInput['arguments'], input);

      final recordedArguments =
          Map<String, String>.from(recordedInput['arguments']! as Map);
      final cast = switch (recordedArguments['method']) {
        'number' => YiJingEngine.castByNumbers(
            int.parse(recordedArguments['first']!),
            int.parse(recordedArguments['second']!),
          ),
        'time' => YiJingEngine.castByTime(
            DateTime.parse(recordedArguments['at']!),
          ),
        'manual' => YiJingEngine.castManual(
            int.parse(recordedArguments['upper']!),
            int.parse(recordedArguments['lower']!),
            int.parse(recordedArguments['moving']!),
          ),
        'coins' => YiJingEngine.castByCoins(
            recordedArguments['coins']!
                .split(',')
                .map(int.parse)
                .toList(growable: false),
          ),
        _ => throw StateError('Unsupported test method'),
      };
      expect(
        YiJingToolExecutor.matchesCast(snapshot: snapshot, cast: cast),
        isTrue,
      );
      if (input['method'] != 'coins') {
        expect(
          result['movingTitles'],
          [cast.movingTitle],
          reason: '数字/时间/手动起卦应保留 legacy executor 的单动爻表示',
        );
        expect(
          result['movingTexts'],
          [cast.movingText],
        );
      }
    }
  });

  test('YiJing resolver binds exact method, sources, rule and rebuilt result', () {
    const arguments = {'method': 'number', 'first': '3', 'second': '7'};
    final snapshot = YiJingToolExecutor.createStructuredSnapshot(arguments);
    final ref = AiContextResolver.buildYiJingResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolved = AiContextResolver.resolveYiJingToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'yijing');
    expect(ref.sourceId, YiJingToolExecutor.sourceId);
    expect(ref.snapshotId, snapshot['snapshotId']);
    expect(resolved.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildYiJingToolResult(
      resolvedResult: resolved.value!,
    );
    expect(prompt, contains('本卦'));
    expect(prompt, contains('变卦'));
    expect(prompt, contains('King Wen'));
    expect(prompt, contains('不把结果表述为科学预测'));

    final staleRule = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'yijing-engine@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYiJingToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:yijing',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYiJingToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final changedMethodAnchor = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId.replaceFirst('method=number', 'method=time'),
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYiJingToolResult(
        ref: changedMethodAnchor,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final tampered = Map<String, Object?>.from(snapshot);
    final tamperedResult = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    )..['moving'] = 6;
    tampered['result'] = tamperedResult;
    expect(
      AiContextResolver.resolveYiJingToolResult(
        ref: ref,
        structuredSnapshot: tampered,
      ).status,
      AiContextResolutionStatus.stale,
    );
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: ref,
        structuredSnapshot: tampered,
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'YiJingScreen preserves the real number inputs and opens explanation-only AI from the result',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 1000);
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
            home: const YiJingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '3');
      await tester.enterText(fields.at(1), '7');

      final castButtons = find.widgetWithText(FilledButton, '起卦');
      expect(castButtons, findsNWidgets(3));
      await tester.tap(castButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.byType(YiJingResultScreen), findsOneWidget);
      final ask = find.byTooltip('问 AI 解读当前卦象');
      expect(ask, findsOneWidget);

      await tester.tap(ask);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final assistantWidget = tester.widget<LocalAiInterviewScreen>(assistant);
      expect(assistantWidget.initialMode, AssistantMode.tools);
      expect(assistantWidget.contextualExplanationOnly, isTrue);
      expect(assistantWidget.contextRef['kind'], 'toolResult');
      expect(assistantWidget.contextRef['moduleId'], 'yijing');
      expect(assistantWidget.contextRef['snapshotId'], hasLength(64));
      expect(assistantWidget.initialPrompt, contains('易经起卦结果'));
      expect(tester.takeException(), isNull);
    },
  );
}
