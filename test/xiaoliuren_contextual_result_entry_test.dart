import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/xiaoliuren_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/xiaoliuren_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const arguments = {
    'date': '2026-11-14',
    'hour': '午时',
    'rule': 'common',
  };
  final fixedNow = DateTime(2026, 11, 18, 12);

  test('两种起课口径均生成可重建的来源绑定快照', () {
    for (final rule in ['common', 'duoneng']) {
      final input = {...arguments, 'rule': rule};
      final execution = XiaoliurenToolExecutor.executeWithSnapshot(
        input,
        now: fixedNow,
      );
      expect(execution.succeeded, isTrue);
      expect(execution.result.validateArgumentsMatch(input), isEmpty);

      final snapshot = execution.structuredSnapshot!;
      final sourceInput = snapshot['input']! as Map<String, Object?>;
      final result = snapshot['result']! as Map<String, Object?>;
      expect(sourceInput['executionDate'], '2026-11-18');
      expect(sourceInput['arguments'], input);
      expect(result['month'], isA<Map<String, Object?>>());
      expect(result['day'], isA<Map<String, Object?>>());
      expect(result['hour'], isA<Map<String, Object?>>());
      expect(result['palaceOrder'], hasLength(6));
      expect(
        AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
        snapshot['snapshotId'],
      );

      final ref = AiContextResolver.buildXiaoliurenResultContextRef(
        structuredSnapshot: snapshot,
      );
      final resolution = AiContextResolver.resolveXiaoliurenToolResult(
        ref: ref,
        structuredSnapshot: snapshot,
      );
      expect(ref.kind, AiContextKind.toolResult);
      expect(ref.moduleId, 'xiaoliuren');
      expect(ref.snapshotId, hasLength(64));
      expect(ref.ruleVersion, XiaoliurenToolExecutor.ruleVersion);
      expect(resolution.isResolved, isTrue);

      final prompt = AiContextPromptBuilder.buildXiaoliurenToolResult(
        resolvedResult: resolution.value!,
      );
      expect(prompt, contains('小六壬'));
      expect(prompt, contains('农历'));
      expect(prompt, contains(ref.snapshotId!));
      expect(prompt, contains('不得重新排盘、推算'));
      expect(prompt, contains('民俗文化参考'));
    }
  });

  test('小六壬结果 Resolver 拒绝错源、过期规则和篡改快照', () {
    final execution = XiaoliurenToolExecutor.executeWithSnapshot(
      arguments,
      now: fixedNow,
    );
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildXiaoliurenResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:xiaoliuren',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveXiaoliurenToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final staleRule = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'xiaoliuren-engine@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveXiaoliurenToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final changedResult = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    )..['hour'] = {'palace': {'name': '伪造结果'}};
    final tampered = {...snapshot, 'result': changedResult};
    expect(
      AiContextResolver.resolveXiaoliurenToolResult(
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

  test('失败执行不会建立可供 AI 使用的结果快照', () {
    final missingRule = XiaoliurenToolExecutor.executeWithSnapshot(
      const {'date': '2026-11-14', 'hour': '午时'},
      now: fixedNow,
    );
    expect(missingRule.succeeded, isFalse);
    expect(missingRule.structuredSnapshot, isNull);
    expect(missingRule.result.sourceIds, isEmpty);

    final unsupportedArgument = XiaoliurenToolExecutor.executeWithSnapshot(
      {...arguments, 'rawPrompt': '推测一个结果'},
      now: fixedNow,
    );
    expect(unsupportedArgument.succeeded, isFalse);
    expect(unsupportedArgument.structuredSnapshot, isNull);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, expectsSheet: true),
    (width: 775.0, height: 1100.0, expectsSheet: false),
  ]) {
    testWidgets(
      '小六壬真实页面在 ${viewport.width.toInt()}dp 窗口打开同一结果情境助手并保留滚动位置',
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
              home: const XiaoliurenScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ask = find.text('问 AI 解读当前小六壬结果');
        expect(ask, findsOneWidget);
        await tester.ensureVisible(ask);
        await tester.pumpAndSettle();

        final pageScrollable = find.ancestor(
          of: ask,
          matching: find.byType(Scrollable),
        ).first;
        final pagePosition =
            tester.state<ScrollableState>(pageScrollable).position;
        final offsetBeforeOpen = pagePosition.pixels;

        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final assistantWidget =
            tester.widget<LocalAiInterviewScreen>(assistant);
        expect(assistantWidget.initialMode, AssistantMode.metaphysics);
        expect(assistantWidget.contextualExplanationOnly, isTrue);
        expect(assistantWidget.contextRef['kind'], 'toolResult');
        expect(assistantWidget.contextRef['moduleId'], 'xiaoliuren');
        expect(assistantWidget.contextRef['snapshotId'], hasLength(64));
        expect(assistantWidget.initialPrompt, contains('小六壬'));
        expect(assistantWidget.initialPrompt, contains('午时'));
        if (viewport.expectsSheet) {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        } else {
          expect(find.byType(Dialog), findsWidgets);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistant),
          rootNavigator: true,
        ).pop();
        await tester.pumpAndSettle();

        expect(find.byType(XiaoliurenScreen), findsOneWidget);
        final restoredScrollable = find.ancestor(
          of: ask,
          matching: find.byType(Scrollable),
        ).first;
        final restoredPosition =
            tester.state<ScrollableState>(restoredScrollable).position;
        expect(
          restoredPosition.pixels,
          closeTo(offsetBeforeOpen, 0.5),
          reason: '关闭情境助手后必须保留小六壬页面滚动位置',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
