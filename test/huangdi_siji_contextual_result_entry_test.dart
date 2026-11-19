import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/huangdi_siji_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/huangdi_siji_result_context_executor.dart';
import 'package:nihaisha_app/services/huangdi_siji_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const arguments = {
    'birth_date': '1990-01-02',
    'birth_time': '16:30',
  };

  test('四季歌真实 Headless 结果生成稳定来源绑定结构化快照', () async {
    final execution =
        await HuangdiSijiResultContextExecutor.executeWithSnapshot(arguments);
    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('huangdi_siji'), isEmpty);
    expect(execution.result.validateArgumentsMatch(arguments), isEmpty);
    expect(execution.result.sourceIds, [
      HuangdiSijiToolExecutor.sourceId,
      HuangdiSijiToolExecutor.dataSourceId,
    ]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'huangdi_siji');
    expect(snapshot['resultSchemaVersion'],
        HuangdiSijiResultContextExecutor.resultSchemaVersion);
    expect(snapshot['ruleVersion'], HuangdiSijiResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect((input['arguments'] as Map)['birth_date'], '1990-01-02');
    expect((input['arguments'] as Map)['birth_time'], '16:30');
    expect(values['对应部位'], isNotEmpty);
    expect(values['部位诗'], isNotEmpty);
    expect(snapshot['privacy'], {
      'exactBirthDateAndTime': 'LOCAL_VERIFICATION_ONLY',
      'modelPromptPolicy': 'REDACT_EXACT_BIRTH_DATE_AND_TIME',
    });
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final repeated =
        await HuangdiSijiResultContextExecutor.executeWithSnapshot(arguments);
    expect(
      repeated.structuredSnapshot!['snapshotId'],
      snapshot['snapshotId'],
    );
  });

  test('Resolver 与 Prompt 只接受正确来源、规则和完整快照', () async {
    final execution =
        await HuangdiSijiResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildHuangdiSijiResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveHuangdiSijiToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );
    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'huangdi_siji');
    expect(ref.sourceId, HuangdiSijiToolExecutor.sourceId);
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildHuangdiSijiToolResult(
      resolvedResult: resolution.value!,
    );
    expect(prompt, contains('传统民俗通胜文本'));
    expect(prompt, contains('REDACTED_LOCAL_ONLY'));
    expect(prompt, isNot(contains('1990-01-02')));
    expect(prompt, isNot(contains('16:30')));
    expect(prompt, contains('不得尝试反推'));
  });

  test('Resolver 拒绝错源、过期规则和被篡改的结果', () async {
    final execution =
        await HuangdiSijiResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildHuangdiSijiResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:huangdi-siji',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveHuangdiSijiToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.unknown,
    );

    final staleRule = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'huangdi-siji@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveHuangdiSijiToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final changed = Map<String, Object?>.from(snapshot['result']! as Map);
    final changedValues =
        Map<String, Object?>.from(changed['values']! as Map);
    changedValues['部位诗'] = '伪造诗文';
    changed['values'] = changedValues;
    final tampered = {...snapshot, 'result': changed};
    expect(
      (await AiContextResolver.resolveHuangdiSijiToolResult(
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

  test('失败或未声明参数不会生成可供 AI 使用的快照', () async {
    final missingTime =
        await HuangdiSijiResultContextExecutor.executeWithSnapshot(
      const {'birth_date': '1990-01-02'},
    );
    expect(missingTime.succeeded, isFalse);
    expect(missingTime.structuredSnapshot, isNull);
    expect(missingTime.result.sourceIds, isEmpty);

    final extra =
        await HuangdiSijiResultContextExecutor.executeWithSnapshot({
      ...arguments,
      'rawPrompt': '从出生日期推断未来疾病',
    });
    expect(extra.succeeded, isFalse);
    expect(extra.structuredSnapshot, isNull);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, isSidePanel: false),
    (width: 775.0, height: 1100.0, isSidePanel: true),
  ]) {
    testWidgets(
      '四季歌页面在 ${viewport.width.toInt()}dp 打开当前结果情境助手并保留滚动',
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
              home: const HuangdiSijiScreen(returnResultOnComplete: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pageScrollable = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Scrollable),
        ).first;
        final query = find.text('查询四季歌');
        await tester.ensureVisible(query);
        await tester.tap(query);
        await tester.pumpAndSettle();

        final ask = find.text('问 AI 解读当前四季歌结果');
        await tester.scrollUntilVisible(
          ask,
          180,
          scrollable: pageScrollable,
        );
        await tester.pumpAndSettle();
        expect(ask, findsOneWidget);
        expect(find.text('将本次四季歌结果带回助手对话'), findsOneWidget);

        final position = tester.state<ScrollableState>(pageScrollable).position;
        final offsetBeforeOpen = position.pixels;
        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.metaphysics);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'huangdi_siji');
        expect(widget.contextRef['snapshotId'], hasLength(64));
        expect(widget.initialPrompt, contains('REDACTED_LOCAL_ONLY'));
        expect(widget.initialPrompt, isNot(contains('1990-01-01')));
        if (viewport.isSidePanel) {
          expect(find.byType(Dialog), findsWidgets);
        } else {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(assistant), rootNavigator: true).pop();
        await tester.pumpAndSettle();
        expect(find.byType(HuangdiSijiScreen), findsOneWidget);
        final restored = tester.state<ScrollableState>(pageScrollable).position;
        expect(restored.pixels, closeTo(offsetBeforeOpen, 0.5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
