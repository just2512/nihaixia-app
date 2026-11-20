import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/data/shousheng_data.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/shousheng_debt_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/shousheng_debt_result_context_executor.dart';
import 'package:nihaisha_app/services/shousheng_debt_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = SettingsRepository.instance;
    if (!settings.isLoaded) await settings.load();
    await ShoushengData.ensureLoaded();
  });

  const cases = [
    {
      'method': 'luku',
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
    },
    {
      'method': 'wudou',
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
    },
  ];

  test('禄库受生经与五斗金章两套真实结果均生成稳定的来源绑定快照', () async {
    for (final args in cases) {
      final execution =
          await ShoushengDebtResultContextExecutor.executeWithSnapshot(args);
      expect(execution.succeeded, isTrue);
      expect(execution.result.validateFor('shousheng_debt'), isEmpty);
      expect(execution.result.validateArgumentsMatch(args), isEmpty);

      final method = args['method']!;
      final expectedData = method == 'luku'
          ? ShoushengDebtToolExecutor.lukuDataSourceId
          : ShoushengDebtToolExecutor.wudouDataSourceId;
      final snapshot = execution.structuredSnapshot!;
      final input = snapshot['input']! as Map<String, Object?>;
      final result = snapshot['result']! as Map<String, Object?>;
      expect(snapshot['capabilityId'], 'shousheng_debt');
      expect(snapshot['resultSchemaVersion'],
          ShoushengDebtResultContextExecutor.resultSchemaVersion);
      expect(snapshot['ruleVersion'],
          ShoushengDebtResultContextExecutor.ruleVersion);
      expect(snapshot['executionStatus'], 'SUCCESS');
      expect(snapshot['sourceIds'], [
        ShoushengDebtToolExecutor.sourceId,
        expectedData,
      ]);
      expect((input['arguments'] as Map)['method'], method);
      expect(input['settings'], isA<Map<String, Object?>>());
      expect((result['values'] as Map)['查询体系'],
          method == 'luku' ? '禄库受生经' : '五斗金章受生经');
      expect(
        AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
        snapshot['snapshotId'],
      );

      final repeated =
          await ShoushengDebtResultContextExecutor.executeWithSnapshot(args);
      expect(
        repeated.structuredSnapshot!['snapshotId'],
        snapshot['snapshotId'],
      );
    }
  });

  test('Resolver 和 Prompt 两套口径都准确回链，并向模型脱敏精确生辰', () async {
    for (final args in cases) {
      final execution =
          await ShoushengDebtResultContextExecutor.executeWithSnapshot(args);
      final snapshot = execution.structuredSnapshot!;
      final ref = AiContextResolver.buildShoushengDebtResultContextRef(
        structuredSnapshot: snapshot,
      );
      final resolution = await AiContextResolver.resolveShoushengDebtToolResult(
        ref: ref,
        structuredSnapshot: snapshot,
      );
      expect(ref.kind, AiContextKind.toolResult);
      expect(ref.moduleId, 'shousheng_debt');
      expect(ref.sourceId, ShoushengDebtToolExecutor.sourceId);
      expect(ref.anchorId, contains('method=' + args['method']!));
      expect(resolution.isResolved, isTrue);

      final prompt = AiContextPromptBuilder.buildShoushengDebtToolResult(
        resolvedResult: resolution.value!,
      );
      expect(prompt, contains('REDACTED_LOCAL_ONLY'));
      expect(prompt, isNot(contains('1990-01-02')));
      expect(prompt, isNot(contains('08:30')));
      expect(prompt, contains('不得把“受生债”表述为已经证实的现实债务'));
      expect(prompt, contains('不得建议用户购买法事'));
      if (args['method'] == 'wudou') {
        expect(prompt, contains('口径说明'));
        expect(prompt, contains('经文/民间口径说明'));
      }
    }
  });

  test('Resolver fail closed：错来源、过期规则与快照篡改不进入 Prompt', () async {
    const args = {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'method': 'luku',
    };
    final execution =
        await ShoushengDebtResultContextExecutor.executeWithSnapshot(args);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildShoushengDebtResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:shousheng',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveShoushengDebtToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.unknown,
    );
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      ),
      throwsArgumentError,
    );

    final staleRule = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'shousheng@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveShoushengDebtToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final oldResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final oldValues =
        Map<String, Object?>.from(oldResult['values']! as Map);
    oldValues['禄库曹官数据'] = '伪造金额';
    oldResult['values'] = oldValues;
    final tampered = {...snapshot, 'result': oldResult};
    expect(
      (await AiContextResolver.resolveShoushengDebtToolResult(
        ref: ref,
        structuredSnapshot: tampered,
      )).status,
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

  test('非法或未声明参数不会生成可解释快照', () async {
    final invalid = await ShoushengDebtResultContextExecutor.executeWithSnapshot(
      const {
        'birth_date': '1990-01-02',
        'birth_time': '08:30',
        'method': 'guess',
      },
    );
    expect(invalid.succeeded, isFalse);
    expect(invalid.structuredSnapshot, isNull);

    final extra = await ShoushengDebtResultContextExecutor.executeWithSnapshot({
      ...cases.first,
      'gender': 'male',
    });
    expect(extra.succeeded, isFalse);
    expect(extra.structuredSnapshot, isNull);
  });

  testWidgets('查询后修改出生分钟会废弃旧结果，不再开放情境问 AI', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 880);
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
          home: const ShoushengDebtScreen(returnResultOnComplete: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final query = find.text('查询受生债');
    await tester.ensureVisible(query);
    await tester.tap(query);
    await tester.pumpAndSettle();

    final pageScrollable = find.descendant(
      of: find.byType(Scaffold),
      matching: find.byType(Scrollable),
    ).first;
    final ask = find.text('问 AI 解读当前受生债结果');
    await tester.scrollUntilVisible(ask, 180, scrollable: pageScrollable);
    await tester.pumpAndSettle();
    expect(ask, findsOneWidget);
    expect(find.text('将本次受生债查询结果带回助手对话'), findsOneWidget);

    final minuteDropdown = find.byType(DropdownButton<int>).last;
    await tester.tap(minuteDropdown);
    await tester.pumpAndSettle();
    final minuteOne = find.text('01').last;
    await tester.tap(minuteOne);
    await tester.pumpAndSettle();

    expect(find.text('问 AI 解读当前受生债结果'), findsNothing);
    expect(find.text('将本次受生债查询结果带回助手对话'), findsNothing);
    expect(find.text('确认本次受生债查询输入'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, method: 'luku'),
    (width: 775.0, height: 1100.0, method: 'wudou'),
  ]) {
    testWidgets(
      '受生债页面 ${viewport.width.toInt()}dp 绑定所选体系、打开情境助手并保留滚动',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(viewport.width, viewport.height);
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
              home: const ShoushengDebtScreen(returnResultOnComplete: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (viewport.method == 'wudou') {
          await tester.tap(find.text('五斗金章受生经'));
          await tester.pumpAndSettle();
        }
        final query = find.text('查询受生债');
        await tester.ensureVisible(query);
        await tester.tap(query);
        await tester.pumpAndSettle();

        final pageScrollable = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Scrollable),
        ).first;
        final ask = find.text('问 AI 解读当前受生债结果');
        await tester.scrollUntilVisible(
          ask,
          180,
          scrollable: pageScrollable,
        );
        await tester.pumpAndSettle();
        expect(ask, findsOneWidget);
        expect(find.text('将本次受生债查询结果带回助手对话'), findsOneWidget);

        final position = tester.state<ScrollableState>(pageScrollable).position;
        final offsetBeforeOpen = position.pixels;
        await tester.tap(ask);
        await tester.pumpAndSettle();

        expect(find.text('确认本次受生债查询输入'), findsOneWidget);
        await tester.tap(find.text('确认并解读'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.metaphysics);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'shousheng_debt');
        expect(widget.contextRef['snapshotId'], hasLength(64));
        expect(widget.initialPrompt, contains('REDACTED_LOCAL_ONLY'));
        expect(widget.initialPrompt, isNot(contains('1990-01-01')));
        expect(widget.initialPrompt, isNot(contains('12:00')));
        if (viewport.width < 500) {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        } else {
          expect(find.byType(Dialog), findsWidgets);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(assistant), rootNavigator: true).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        expect(find.byType(ShoushengDebtScreen), findsOneWidget);
        final restored = tester.state<ScrollableState>(pageScrollable).position;
        expect(restored.pixels, closeTo(offsetBeforeOpen, 0.5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
