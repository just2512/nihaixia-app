import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/yuxiaji_omen_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/yuxiaji_omen_result_context_executor.dart';
import 'package:nihaisha_app/services/yuxiaji_omen_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同一设备本地时间生成可重建快照，模型上下文不暴露精确时间', () async {
    final observedAt = DateTime(2026, 11, 16, 0, 30);
    final execution = YuxiajiOmenResultContextExecutor.executeWithSnapshot(
      observedAt: observedAt,
    );

    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('yuxiaji_omen'), isEmpty);
    expect(execution.result.validateArgumentsMatch(const {}), isEmpty);
    expect(execution.result.arguments, isEmpty);
    expect(execution.result.sourceIds, [YuxiajiOmenToolExecutor.sourceId]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'yuxiaji_omen');
    expect(
      snapshot['resultSchemaVersion'],
      YuxiajiOmenResultContextExecutor.resultSchemaVersion,
    );
    expect(snapshot['ruleVersion'], YuxiajiOmenResultContextExecutor.ruleVersion);
    expect(input['method'], 'deviceLocalDateTime');
    expect(input['clockOwner'], 'APP_DEVICE_LOCAL');
    expect(input['at'], observedAt.toIso8601String());
    expect(input['utcOffsetMinutes'], observedAt.timeZoneOffset.inMinutes);
    expect(values['App 本机日期时间'], observedAt.toIso8601String());
    expect(values['当前时辰'], '子时 23:00–00:59');
    expect(values['《玉匣记》当前时辰身兆条目'], isNotEmpty);
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final ref = AiContextResolver.buildYuxiajiOmenResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveYuxiajiOmenToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );
    expect(resolution.isResolved, isTrue);
    expect(
      resolution.value!.structuredSnapshot['snapshotId'],
      snapshot['snapshotId'],
    );
    final prompt = AiContextPromptBuilder.buildYuxiajiOmenToolResult(
      resolvedResult: resolution.value!,
    );
    expect(prompt, contains('十二时辰身兆'));
    expect(prompt, contains('面热、眼跳、耳鸣、心惊'));
    expect(prompt, contains('LOCAL_VERIFICATION_ONLY'));
    expect(prompt, isNot(contains(observedAt.toIso8601String())));
    expect(prompt, isNot(contains('本机 UTC 偏移分钟')));
    expect(prompt, contains('不得推断用户存在相应症状'));
  });

  test('拒绝错误来源、过期规则和被篡改的本地时辰结果', () async {
    final execution = YuxiajiOmenResultContextExecutor.executeWithSnapshot(
      observedAt: DateTime(2026, 11, 16, 8, 15),
    );
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildYuxiajiOmenResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'local-data:untrusted-omen',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveYuxiajiOmenToolResult(
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
      ruleVersion: 'yuxiaji@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveYuxiajiOmenToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final changedResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final changedValues =
        Map<String, Object?>.from(changedResult['values']! as Map);
    changedValues['《玉匣记》当前时辰身兆条目'] = '伪造条目';
    changedResult['values'] = changedValues;
    final tampered = {...snapshot, 'result': changedResult};
    expect(
      (await AiContextResolver.resolveYuxiajiOmenToolResult(
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

  test('UTC 输入、额外参数和缺少时间来源均不能生成快照', () {
    final utc = YuxiajiOmenResultContextExecutor.executeWithSnapshot(
      observedAt: DateTime.utc(2026, 11, 16, 8),
    );
    expect(utc.succeeded, isFalse);
    expect(utc.structuredSnapshot, isNull);

    final extra = YuxiajiOmenToolExecutor.execute(
      const {'hour': '子'},
      clock: () => DateTime(2026, 11, 16, 0, 30),
    );
    expect(extra.statusLabel, 'FAILED');
    expect(extra.sourceIds, isEmpty);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, isSidePanel: false),
    (width: 775.0, height: 1100.0, isSidePanel: true),
  ]) {
    testWidgets(
      '玉匣灵兆页面在 ${viewport.width.toInt()}dp 将当前时辰文本带入情境助手',
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
              home: const YuxiajiOmenScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ask = find.text('问 AI 解读当前时辰身兆文本');
        expect(ask, findsOneWidget);
        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.metaphysics);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'yuxiaji_omen');
        expect(widget.contextRef['snapshotId'], hasLength(64));
        expect(widget.contextRef['sourceId'], YuxiajiOmenToolExecutor.sourceId);
        expect(widget.initialPrompt, contains('十二时辰身兆'));
        expect(widget.initialPrompt, contains('LOCAL_VERIFICATION_ONLY'));
        if (viewport.isSidePanel) {
          expect(find.byType(Dialog), findsWidgets);
        } else {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(assistant), rootNavigator: true).pop();
        await tester.pumpAndSettle();
        expect(find.byType(YuxiajiOmenScreen), findsOneWidget);
        expect(ask, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
