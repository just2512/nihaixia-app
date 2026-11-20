import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/sanshan_lingqian_data.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/sanshan_lingqian_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/sanshan_lingqian_result_context_executor.dart';
import 'package:nihaisha_app/services/sanshan_lingqian_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('App 抽签生成稳定的本地签谱快照，重建不会再次随机抽签', () async {
    const seed = 73;
    final expectedIndex = Random(seed).nextInt(kSanShanLingqian.length);
    final execution =
        await SanshanLingqianResultContextExecutor.drawWithSnapshot(
      random: Random(seed),
    );

    expect(execution.succeeded, isTrue);
    expect(execution.sign?.id, kSanShanLingqian[expectedIndex].id);
    expect(execution.result.validateFor('sanshan_lingqian'), isEmpty);
    expect(execution.result.arguments, isEmpty);
    expect(execution.result.sourceIds, [
      '\${SanshanLingqianToolExecutor.dataSourcePrefix}\${execution.sign!.id}',
    ]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'sanshan_lingqian');
    expect(
      snapshot['resultSchemaVersion'],
      SanshanLingqianResultContextExecutor.resultSchemaVersion,
    );
    expect(snapshot['ruleVersion'], SanshanLingqianResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input['method'], 'appRandomDraw');
    expect(input['selectionOwner'], 'APP_LOCAL_ONLY');
    expect(input['selectedSignId'], execution.sign!.id);
    expect(input['arguments'], isEmpty);
    expect(values['签号'], execution.sign!.id.toString());
    expect(values['签题'], execution.sign!.title);
    expect(values['签诗'], execution.sign!.verse);
    expect(values['签级'], execution.sign!.luck.label);
    expect(
      snapshot['sourceIds'],
      ['\${SanshanLingqianToolExecutor.dataSourcePrefix}\${execution.sign!.id}'],
    );
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final rebuilt = await SanshanLingqianResultContextExecutor.executeForSignId(
      execution.sign!.id,
    );
    expect(rebuilt.succeeded, isTrue);
    expect(rebuilt.sign?.id, execution.sign!.id);
    expect(rebuilt.structuredSnapshot!['snapshotId'], snapshot['snapshotId']);
    expect(rebuilt.sign?.verse, execution.sign?.verse);
  });

  test('Resolver 与 Prompt 只接受来源、签号、规则和快照完全一致的结果', () async {
    final execution =
        await SanshanLingqianResultContextExecutor.executeForSignId(17);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildSanshanLingqianResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution =
        await AiContextResolver.resolveSanshanLingqianToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'sanshan_lingqian');
    expect(ref.sourceId, 'local-data:sanshan-lingqian:17');
    expect(ref.anchorId, contains(':sign=17'));
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      structuredSnapshot: resolution.value!.structuredSnapshot,
    );
    expect(prompt, contains('三山国王灵签'));
    expect(prompt, contains(execution.sign!.title));
    expect(prompt, contains(execution.sign!.verse));
    expect(prompt, contains('不是科学预测'));
    expect(prompt, contains('不得重抽、换签'));
    expect(prompt, contains('不得恐吓用户'));
  });

  test('Resolver 拒绝错误来源、过期规则与被篡改的签文', () async {
    final execution =
        await SanshanLingqianResultContextExecutor.executeForSignId(31);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildSanshanLingqianResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'local-data:sanshan-lingqian:32',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveSanshanLingqianToolResult(
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
      ruleVersion: 'sanshan-lingqian@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveSanshanLingqianToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final changedResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final changedValues =
        Map<String, Object?>.from(changedResult['values']! as Map);
    changedValues['签诗'] = '伪造或替换的签诗';
    changedResult['values'] = changedValues;
    final tampered = {...snapshot, 'result': changedResult};
    expect(
      (await AiContextResolver.resolveSanshanLingqianToolResult(
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

  test('签号越界或输入试图指定签号时不生成可供 AI 使用的快照', () async {
    final invalid = await SanshanLingqianResultContextExecutor.executeForSignId(0);
    expect(invalid.succeeded, isFalse);
    expect(invalid.structuredSnapshot, isNull);

    final execution =
        await SanshanLingqianResultContextExecutor.executeForSignId(8);
    final snapshot = execution.structuredSnapshot!;
    final changedInput = Map<String, Object?>.from(snapshot['input']! as Map)
      ..['arguments'] = const {'sign_id': '8'};
    final tampered = {...snapshot, 'input': changedInput};
    expect(
      () => AiContextResolver.buildSanshanLingqianResultContextRef(
        structuredSnapshot: tampered,
      ),
      throwsArgumentError,
    );
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, isSidePanel: false),
    (width: 775.0, height: 1100.0, isSidePanel: true),
  ]) {
    testWidgets(
      '三山灵签页面在 \${viewport.width.toInt()}dp 将当前签文带入情境助手并保留滚动',
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
              home: const SanshanLingqianScreen(returnResultOnComplete: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final query = find.text('摇签');
        await tester.ensureVisible(query);
        await tester.tap(query);
        await tester.pumpAndSettle();

        final listView = find.byType(ListView).first;
        final pageScrollable = find.descendant(
          of: listView,
          matching: find.byType(Scrollable),
        ).first;
        final ask = find.text('问 AI 解读当前灵签结果');
        await tester.scrollUntilVisible(
          ask,
          160,
          scrollable: pageScrollable,
        );
        await tester.pumpAndSettle();

        expect(ask, findsOneWidget);
        expect(find.text('将本次灵签结果带回助手对话'), findsOneWidget);
        final poem =
            tester.widget<SelectableText>(find.byType(SelectableText).first).data;
        final offsetBeforeOpen =
            tester.state<ScrollableState>(pageScrollable).position.pixels;

        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.metaphysics);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'sanshan_lingqian');
        expect(widget.contextRef['snapshotId'], hasLength(64));
        expect(widget.contextRef['sourceId'], startsWith('local-data:sanshan-lingqian:'));
        expect(widget.initialPrompt, contains(poem));
        expect(widget.initialPrompt, contains('不得重抽、换签'));
        if (viewport.isSidePanel) {
          expect(find.byType(Dialog), findsWidgets);
        } else {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(assistant), rootNavigator: true).pop();
        await tester.pumpAndSettle();
        expect(find.byType(SanshanLingqianScreen), findsOneWidget);
        expect(find.text('问 AI 解读当前灵签结果'), findsOneWidget);
        expect(
          tester.state<ScrollableState>(pageScrollable).position.pixels,
          closeTo(offsetBeforeOpen, 0.5),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
