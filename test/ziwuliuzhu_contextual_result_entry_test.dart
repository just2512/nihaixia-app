import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/ziwuliuzhu_screen.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_calculation_service.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const arguments = {'at': '2026-10-08T12:00'};

  test('子午流注四法从同一设备本地时间生成可重建的结构化快照', () {
    final execution = ZiWuLiuZhuToolExecutor.executeWithSnapshot(arguments);
    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('ziwu_liuzhu'), isEmpty);
    expect(execution.result.validateArgumentsMatch(arguments), isEmpty);
    expect(execution.result.values['日干支'], '乙卯');
    expect(execution.result.values['时辰'], '午');

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final methods = result['methods']! as Map<String, Object?>;

    expect(snapshot['capabilityId'], 'ziwu_liuzhu');
    expect(snapshot['resultSchemaVersion'],
        ZiWuLiuZhuToolExecutor.resultSchemaVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(snapshot['sourceIds'], [
      ZiWuLiuZhuToolExecutor.sourceId,
      ZiWuLiuZhuToolExecutor.referenceSourceId,
    ]);
    expect(input['executionDate'], '2026-10-08');
    expect(input['arguments'], arguments);
    expect(input['timeBasis'], contains('device-local wall-clock'));
    expect((input['rules'] as Map)['ziHourDayBoundary'], '23:00');
    expect((methods['naZi'] as Map)['benXue'], '少府');
    expect(methods['naJia'], isA<Map<String, Object?>>());
    expect(methods['lingGui'], isA<Map<String, Object?>>());
    expect(methods['feiTeng'], isA<Map<String, Object?>>());
    expect(result['values'], execution.result.values);
    expect(snapshot['missingFields'], isEmpty);
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final rebuilt = ZiWuLiuZhuToolExecutor.executeWithSnapshot(arguments);
    expect(
      rebuilt.structuredSnapshot!['snapshotId'],
      snapshot['snapshotId'],
      reason: '相同本地时间和相同规则必须重建为相同快照。',
    );
  });

  test('Resolver 和 Prompt 仅接受当前来源、规则与完整快照', () {
    final execution = ZiWuLiuZhuToolExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildZiWuLiuZhuResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = AiContextResolver.resolveZiWuLiuZhuToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'ziwu_liuzhu');
    expect(ref.sourceId, ZiWuLiuZhuToolExecutor.sourceId);
    expect(ref.anchorId, contains('at=2026-10-08T12:00'));
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildZiWuLiuZhuToolResult(
      resolvedResult: resolution.value!,
    );
    expect(prompt, contains('纳子法'));
    expect(prompt, contains('纳甲法'));
    expect(prompt, contains('灵龟八法'));
    expect(prompt, contains('飞腾八法'));
    expect(prompt, contains('120E/30N'));
    expect(prompt, contains('不得补造穴位'));
    expect(prompt, contains('不构成针刺'));
  });

  test('错源、过期规则、篡改结果与无效时间锚点 fail closed', () {
    final execution = ZiWuLiuZhuToolExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildZiWuLiuZhuResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:ziwuliuzhu',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveZiWuLiuZhuToolResult(
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
      ruleVersion: 'ziwuliuzhu-engine@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveZiWuLiuZhuToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final oldResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final oldMethods = Map<String, Object?>.from(oldResult['methods']! as Map);
    final oldNaZi = Map<String, Object?>.from(oldMethods['naZi']! as Map);
    oldNaZi['benXue'] = '伪造穴位';
    oldMethods['naZi'] = oldNaZi;
    oldResult['methods'] = oldMethods;
    final tampered = {...snapshot, 'result': oldResult};
    expect(
      AiContextResolver.resolveZiWuLiuZhuToolResult(
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

    final invalidAnchor = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: 'ziwuliuzhu:result:${ref.snapshotId}:at=2026-02-30T10:30',
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveZiWuLiuZhuToolResult(
        ref: invalidAnchor,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );
  });

  test('失败执行不会生成可供 AI 使用的快照', () {
    final missingTime =
        ZiWuLiuZhuToolExecutor.executeWithSnapshot(const {'date': '2026-11-14'});
    expect(missingTime.succeeded, isFalse);
    expect(missingTime.structuredSnapshot, isNull);
    expect(missingTime.result.sourceIds, isEmpty);

    final invalidOffset = ZiWuLiuZhuToolExecutor.executeWithSnapshot(
      const {'at': '2026-11-14T10:30+08:00'},
    );
    expect(invalidOffset.succeeded, isFalse);
    expect(invalidOffset.structuredSnapshot, isNull);

    final unsupportedArgument = ZiWuLiuZhuToolExecutor.executeWithSnapshot(
      const {'at': '2026-11-14T10:30', 'needle': '少府'},
    );
    expect(unsupportedArgument.succeeded, isFalse);
    expect(unsupportedArgument.structuredSnapshot, isNull);
  });

  test('工具执行兼容既有结果摘要与页面计算口径', () {
    final at = DateTime(2026, 10, 8, 12);
    final calculation = ZiWuLiuZhuCalculationService.calculate(at);
    final execution = ZiWuLiuZhuToolExecutor.executeWithSnapshot(arguments);
    expect(execution.result.values, calculation.values);
    expect(execution.calculationResult?.summary, calculation.summary);
  });

  for (final viewport in [
    (name: '外屏 402dp', width: 402.0, height: 880.0, sidePanel: false),
    (name: '展开内屏 775dp', width: 775.0, height: 1100.0, sidePanel: true),
  ]) {
    testWidgets(
      '子午流注真实页面在${viewport.name}打开绑定当前结果的情境助手并恢复滚动位置',
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
              home: ZiWuLiuZhuScreen(
                initialDate: DateTime(2026, 10, 8, 12),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ask = find.byTooltip('问 AI 解读当前子午流注结果');
        expect(ask, findsOneWidget);

        final tabPage = find.byType(TabBarView);
        final pageList = find.descendant(
          of: tabPage,
          matching: find.byType(ListView),
        ).first;
        final pageScrollable = find.descendant(
          of: pageList,
          matching: find.byType(Scrollable),
        ).first;
        final pagePosition =
            tester.state<ScrollableState>(pageScrollable).position;
        expect(pagePosition.maxScrollExtent, greaterThan(0));
        pagePosition.jumpTo(48);
        await tester.pump();

        final offsetBeforeOpen = pagePosition.pixels;
        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final assistantWidget =
            tester.widget<LocalAiInterviewScreen>(assistant);
        expect(assistantWidget.initialMode, AssistantMode.tools);
        expect(assistantWidget.contextualExplanationOnly, isTrue);
        expect(assistantWidget.contextRef['kind'], 'toolResult');
        expect(assistantWidget.contextRef['moduleId'], 'ziwu_liuzhu');
        expect(assistantWidget.contextRef['snapshotId'], hasLength(64));
        expect(
          assistantWidget.contextRef['anchorId'],
          contains('at=2026-10-08T12:00'),
        );
        expect(assistantWidget.initialPrompt, contains('纳子法'));
        expect(assistantWidget.initialPrompt, contains('灵龟八法'));
        expect(assistantWidget.initialPrompt, contains('不得据此推断疾病'));
        if (viewport.sidePanel) {
          expect(find.byType(Dialog), findsWidgets);
        } else {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistant),
          rootNavigator: true,
        ).pop();
        await tester.pumpAndSettle();

        expect(find.byType(ZiWuLiuZhuScreen), findsOneWidget);
        final restoredPageList = find.descendant(
          of: find.byType(TabBarView),
          matching: find.byType(ListView),
        ).first;
        final restoredScrollable = find.descendant(
          of: restoredPageList,
          matching: find.byType(Scrollable),
        ).first;
        final restoredPosition =
            tester.state<ScrollableState>(restoredScrollable).position;
        expect(
          restoredPosition.pixels,
          closeTo(offsetBeforeOpen, 0.5),
          reason: '关闭情境助手后必须保留当前子午流注页面的滚动位置',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
