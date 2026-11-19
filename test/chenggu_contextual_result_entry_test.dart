import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/chenggu_data.dart';
import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/chenggu_bone_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/chenggu_result_context_executor.dart';
import 'package:nihaisha_app/services/chenggu_tool_executor.dart';
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
    await ChengguData.ensureLoaded();
  });

  const arguments = {
    'birth_date': '1990-01-02',
    'birth_time': '08:30',
  };

  test('称骨真实 Headless 结果生成稳定的来源绑定快照', () async {
    final execution =
        await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('chenggu'), isEmpty);
    expect(execution.result.validateArgumentsMatch(arguments), isEmpty);
    expect(execution.result.sourceIds, const [
      ChengguToolExecutor.sourceId,
      ChengguToolExecutor.dataSourceId,
    ]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'chenggu');
    expect(snapshot['resultSchemaVersion'],
        ChengguResultContextExecutor.resultSchemaVersion);
    expect(snapshot['ruleVersion'], ChengguResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect((input['arguments'] as Map)['birth_date'], '1990-01-02');
    expect((input['arguments'] as Map)['birth_time'], '08:30');
    expect(input['settings'], isA<Map<String, Object?>>());
    expect(values['总骨重'], isNotEmpty);
    expect(values['称骨歌诀'], isNotEmpty);
    expect(values['称骨说明'], isNotEmpty);
    expect(snapshot['privacy'], {
      'exactBirthDateAndTime': 'LOCAL_VERIFICATION_ONLY',
      'modelPromptPolicy': 'REDACT_EXACT_BIRTH_DATE_AND_TIME',
    });
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final repeated =
        await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    expect(
      repeated.structuredSnapshot!['snapshotId'],
      snapshot['snapshotId'],
    );
  });

  test('Resolver 与 Prompt 精确回链，且模型上下文不包含精确生辰', () async {
    final execution =
        await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildChengguResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveChengguToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );
    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'chenggu');
    expect(ref.sourceId, ChengguToolExecutor.sourceId);
    expect(ref.anchorId, contains('chenggu:result:'));
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildChengguToolResult(
      resolvedResult: resolution.value!,
    );
    expect(prompt, contains('REDACTED_LOCAL_ONLY'));
    expect(prompt, isNot(contains('1990-01-02')));
    expect(prompt, isNot(contains('08:30')));
    expect(prompt, contains('不是科学预测'));
    expect(prompt, contains('不得把称骨结果转换为疾病诊断'));
    expect(prompt, contains('不得自行重排四柱'));
  });

  test('Resolver fail closed：错源、过期规则与结果篡改不进入 Prompt', () async {
    final execution =
        await ChengguResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildChengguResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:chenggu',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveChengguToolResult(
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
      ruleVersion: 'chenggu@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveChengguToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final changed = Map<String, Object?>.from(snapshot['result']! as Map);
    final values = Map<String, Object?>.from(changed['values']! as Map);
    values['称骨歌诀'] = '篡改的歌诀';
    changed['values'] = values;
    final tampered = {...snapshot, 'result': changed};
    expect(
      (await AiContextResolver.resolveChengguToolResult(
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

  test('无效输入、未声明参数不会产生可解释快照', () async {
    final missingTime =
        await ChengguResultContextExecutor.executeWithSnapshot(
      const {'birth_date': '1990-01-02'},
    );
    expect(missingTime.succeeded, isFalse);
    expect(missingTime.structuredSnapshot, isNull);

    final extra = await ChengguResultContextExecutor.executeWithSnapshot({
      ...arguments,
      'gender': 'male',
    });
    expect(extra.succeeded, isFalse);
    expect(extra.structuredSnapshot, isNull);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0),
    (width: 775.0, height: 1100.0),
  ]) {
    testWidgets(
      '称骨页面宽度 ' + viewport.width.toInt().toString() + 'dp：真实结果情境助手与滚动恢复',
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
              home: const ChengguBoneScreen(returnResultOnComplete: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pageScrollable = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Scrollable),
        ).first;
        final compute = find.text('称骨测算');
        await tester.ensureVisible(compute);
        await tester.tap(compute);
        await tester.pumpAndSettle();

        final ask = find.text('问 AI 解读当前称骨结果');
        await tester.scrollUntilVisible(
          ask,
          180,
          scrollable: pageScrollable,
        );
        await tester.pumpAndSettle();
        expect(ask, findsOneWidget);
        expect(find.text('将本次称骨结果带回助手对话'), findsOneWidget);

        final position = tester.state<ScrollableState>(pageScrollable).position;
        final offsetBeforeOpen = position.pixels;
        await tester.tap(ask);
        await tester.pumpAndSettle();
        expect(find.text('确认本次称骨查询输入'), findsOneWidget);
        await tester.tap(find.text('确认并解读'));
        await tester.pumpAndSettle();

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.metaphysics);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'chenggu');
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
        await tester.pumpAndSettle();
        expect(find.byType(ChengguBoneScreen), findsOneWidget);
        final restored = tester.state<ScrollableState>(pageScrollable).position;
        expect(restored.pixels, closeTo(offsetBeforeOpen, 0.5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
