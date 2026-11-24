import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/allow_context_authorizer.dart';
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
          TestAuthorizedFeatureScope(
            child: ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: AppColors.colorSchemeFor(Brightness.light),
            extensions: [AppColors.light],
          ),
            home: const YiJingScreen(),
          ),
        )
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
  test('YiJing field resolver binds scalar paths to the exact immutable result', () {
    const arguments = {'method': 'number', 'first': '3', 'second': '7'};
    final snapshot = YiJingToolExecutor.createStructuredSnapshot(arguments);
    final result = snapshot['result']! as Map<String, Object?>;
    final primary = result['primary']! as Map<String, Object?>;
    final parentRef = AiContextResolver.buildYiJingResultContextRef(
      structuredSnapshot: snapshot,
    );
    final fieldRef = AiContextResolver.buildYiJingFieldContextRef(
      resultRef: parentRef,
      fieldPath: 'result.primary.judgement',
      fieldLabel: '本卦卦辞',
    );
    final resolved = AiContextResolver.resolveYiJingResultField(
      ref: fieldRef,
      structuredSnapshot: snapshot,
    );

    expect(resolved.isResolved, isTrue);
    expect(fieldRef.kind, AiContextKind.fieldValue);
    expect(fieldRef.moduleId, 'yijing');
    expect(fieldRef.fieldPath, 'result.primary.judgement');
    expect(fieldRef.snapshotId, snapshot['snapshotId']);
    expect(resolved.value?.fieldValue.single['value'], primary['judgement']);
    expect(
      resolved.value?.structuredSnapshot['snapshotId'],
      snapshot['snapshotId'],
    );

    final prompt = AiContextPromptBuilder.buildYiJingToolField(
      resolvedField: resolved.value!,
    );
    expect(prompt, contains('result.primary.judgement'));
    expect(prompt, contains('本卦卦辞'));
    expect(prompt, contains('不得重新起卦'));
    expect(prompt, contains('不是科学预测'));

    final movingRef = AiContextResolver.buildYiJingFieldContextRef(
      resultRef: parentRef,
      fieldPath: 'result.movingTexts.0',
      fieldLabel: '当前动爻/卦辞',
    );
    final moving = AiContextResolver.resolveYiJingResultField(
      ref: movingRef,
      structuredSnapshot: snapshot,
    );
    expect(moving.isResolved, isTrue);
    expect(
      moving.value?.fieldValue.single['value'],
      (result['movingTexts']! as List).first,
    );

    expect(
      () => AiContextResolver.buildYiJingFieldContextRef(
        resultRef: parentRef,
        fieldPath: 'result.input.untrusted',
        fieldLabel: '不支持路径',
      ),
      throwsArgumentError,
    );

    final stale = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: fieldRef.moduleId,
      anchorId: fieldRef.anchorId,
      anchorVersion: fieldRef.anchorVersion,
      snapshotId: fieldRef.snapshotId,
      ruleVersion: 'yijing-engine@STALE',
      sourceId: fieldRef.sourceId,
      fieldPath: fieldRef.fieldPath,
      title: fieldRef.title,
    );
    expect(
      AiContextResolver.resolveYiJingResultField(
        ref: stale,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final tampered = Map<String, Object?>.from(snapshot);
    final tamperedResult = Map<String, Object?>.from(result);
    final tamperedPrimary = Map<String, Object?>.from(primary)
      ..['judgement'] = '被篡改的卦辞';
    tamperedResult['primary'] = tamperedPrimary;
    tampered['result'] = tamperedResult;
    expect(
      AiContextResolver.resolveYiJingResultField(
        ref: fieldRef,
        structuredSnapshot: tampered,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final missingArguments = const {
      'method': 'manual',
      'upper': '1',
      'lower': '8',
      'moving': '0',
    };
    final missingSnapshot =
        YiJingToolExecutor.createStructuredSnapshot(missingArguments);
    final missingParent = AiContextResolver.buildYiJingResultContextRef(
      structuredSnapshot: missingSnapshot,
    );
    final absentField = AiContextResolver.buildYiJingFieldContextRef(
      resultRef: missingParent,
      fieldPath: 'result.changed.judgement',
      fieldLabel: '变卦卦辞',
    );
    expect(
      AiContextResolver.resolveYiJingResultField(
        ref: absentField,
        structuredSnapshot: missingSnapshot,
      ).status,
      AiContextResolutionStatus.missing,
    );
  });

  testWidgets(
    'YiJing result exposes a real field-bound explanation-only assistant entry',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 1100);
      addTearDown(tester.view.reset);

      const arguments = {'method': 'number', 'first': '3', 'second': '7'};
      final cast = YiJingEngine.castByNumbers(3, 7);
      await tester.pumpWidget(
          TestAuthorizedFeatureScope(
            child: ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(Brightness.light),
              extensions: [AppColors.light],
            ),
            home: YiJingResultScreen(
              cast: cast,
              executionArguments: arguments,
            ),
          ),
        )
          ),
        );
      await tester.pumpAndSettle();

      final fieldAsk = find.byKey(
        const ValueKey('yijing-field-primary-judgement'),
      );
      expect(fieldAsk, findsOneWidget);
      expect(find.byTooltip('问 AI 解读当前卦象'), findsOneWidget);

      await tester.tap(fieldAsk);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final widget = tester.widget<LocalAiInterviewScreen>(assistant);
      expect(widget.initialMode, AssistantMode.tools);
      expect(widget.contextualExplanationOnly, isTrue);
      expect(widget.contextRef['kind'], 'field');
      expect(widget.contextRef['moduleId'], 'yijing');
      expect(widget.contextRef['fieldPath'], 'result.primary.judgement');
      expect(widget.contextRef['snapshotId'], hasLength(64));
      expect(widget.initialPrompt, contains('本卦卦辞'));
      expect(widget.initialPrompt, contains('不得重新起卦'));
      expect(tester.takeException(), isNull);
    },
  );

}
