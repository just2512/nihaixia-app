import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/solar_term_section_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/solar_term_result_context_executor.dart';
import 'package:nihaisha_app/services/solar_term_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('指定节气生成包含原始知识来源的稳定结构化快照', () async {
    final execution =
        await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': '立春',
    });
    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('solar_terms'), isEmpty);
    expect(execution.result.validateArgumentsMatch({'term': '立春'}), isEmpty);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'solar_terms');
    expect(snapshot['resultSchemaVersion'],
        SolarTermResultContextExecutor.resultSchemaVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(snapshot['sourceIds'], [
      SolarTermToolExecutor.sourceId,
      SolarTermToolExecutor.knowledgeSourceId,
    ]);
    expect(input['method'], 'explicitSolarTerm');
    expect(input['arguments'], {'term': '立春'});
    expect(result['term'], '立春');
    expect(values['目标节气'], '立春');
    expect(values['倪师讲座相关整理'], contains('【推断】'));
    expect(values['起居调摄'], contains('【推断】'));
    expect(snapshot['missingFields'], isEmpty);
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final repeated =
        await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': '立春',
    });
    expect(
      repeated.structuredSnapshot!['snapshotId'],
      snapshot['snapshotId'],
    );
  });

  test('Resolver 和 Prompt 仅接受当前节气、正确来源与完整快照', () async {
    final execution =
        await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': '立春',
    });
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildSolarTermResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveSolarTermToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'solar_terms');
    expect(ref.sourceId, SolarTermToolExecutor.sourceId);
    expect(ref.anchorId, contains('term=立春'));
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildSolarTermToolResult(
      resolvedResult: resolution.value!,
    );
    expect(prompt, contains('立春'));
    expect(prompt, contains('节气三候'));
    expect(prompt, contains('不得补造节气日期'));
    expect(prompt, contains('不是个体体质评估或诊断'));
  });

  test('Resolver 拒绝错源、过期版本和被篡改的节气资料', () async {
    final execution =
        await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': '立春',
    });
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildSolarTermResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:solar-term',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveSolarTermToolResult(
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
      ruleVersion: 'solar-term-asset@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveSolarTermToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final oldResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final oldValues = Map<String, Object?>.from(oldResult['values']! as Map);
    oldValues['通用养生常识'] = '被篡改的节气建议';
    oldResult['values'] = oldValues;
    final tampered = {...snapshot, 'result': oldResult};
    expect(
      (await AiContextResolver.resolveSolarTermToolResult(
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

  test('无效节气和未声明参数不会产生成功快照', () async {
    final invalid = await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': '不存在',
    });
    expect(invalid.succeeded, isFalse);
    expect(invalid.structuredSnapshot, isNull);
    expect(invalid.result.sourceIds, isEmpty);

    final extra = await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': '立春',
      'rawPrompt': '请推测体质后给药',
    });
    expect(extra.succeeded, isFalse);
    expect(extra.structuredSnapshot, isNull);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, isSidePanel: false),
    (width: 775.0, height: 1100.0, isSidePanel: true),
  ]) {
    testWidgets(
      '节气页面在 ${viewport.width.toInt()}dp 打开绑定指定节气的学习助手并保留滚动',
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
              home: const SolarTermSectionScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ask = find.byTooltip('问 AI 解读立春节气');
        final scrollable = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Scrollable),
        ).first;
        await tester.scrollUntilVisible(
          ask,
          180,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(ask, findsOneWidget);

        final position = tester.state<ScrollableState>(scrollable).position;
        final offsetBeforeOpen = position.pixels;
        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.learning);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'solar_terms');
        expect(widget.contextRef['snapshotId'], hasLength(64));
        expect(widget.contextRef['anchorId'], contains('term=立春'));
        expect(widget.initialPrompt, contains('立春'));
        expect(widget.initialPrompt, contains('【推断】'));
        if (viewport.isSidePanel) {
          expect(find.byType(Dialog), findsWidgets);
        } else {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(assistant), rootNavigator: true).pop();
        await tester.pumpAndSettle();
        final restored = tester.state<ScrollableState>(scrollable).position;
        expect(restored.pixels, closeTo(offsetBeforeOpen, 0.5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
