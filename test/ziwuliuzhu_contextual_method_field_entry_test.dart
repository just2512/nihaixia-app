import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/ziwuliuzhu_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_tool_executor.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const availableArguments = {'at': '2026-10-08T12:00'};
  const unavailableNajiaArguments = {'at': '2026-10-08T10:00'};
  const methodCases = <({String path, String key, String label})>[
    (path: 'methods.naZi', key: 'naZi', label: '纳子法'),
    (path: 'methods.naJia', key: 'naJia', label: '纳甲法'),
    (path: 'methods.lingGui', key: 'lingGui', label: '灵龟八法'),
    (path: 'methods.feiTeng', key: 'feiTeng', label: '飞腾八法'),
  ];

  test('四种方法级字段只解析同一设备本地时间快照中的对应方法', () {
    final execution =
        ZiWuLiuZhuToolExecutor.executeWithSnapshot(availableArguments);
    expect(execution.succeeded, isTrue);
    final snapshot = execution.structuredSnapshot!;
    final result = snapshot['result']! as Map<String, Object?>;
    final methods = result['methods']! as Map<String, Object?>;

    for (final method in methodCases) {
      final ref = AiContextResolver
          .buildZiWuLiuZhuResultFieldContextRef(
        structuredSnapshot: snapshot,
        fieldPath: method.path,
      );
      final resolution =
          AiContextResolver.resolveZiWuLiuZhuResultField(
        ref: ref,
        structuredSnapshot: snapshot,
      );

      expect(ref.kind, AiContextKind.fieldValue);
      expect(ref.moduleId, ZiWuLiuZhuToolExecutor.moduleId);
      expect(ref.fieldPath, method.path);
      expect(ref.sourceId, ZiWuLiuZhuToolExecutor.sourceId);
      expect(ref.snapshotId, snapshot['snapshotId']);
      expect(resolution.isResolved, isTrue, reason: method.path);

      final field = resolution.value!;
      expect(field.fieldValue, hasLength(1));
      expect(field.fieldValue.single['fieldPath'], method.path);
      expect(field.fieldValue.single['value'], methods[method.key]);
      expect(field.structuredSnapshot['snapshotId'], snapshot['snapshotId']);

      final prompt =
          AiContextPromptBuilder.buildZiWuLiuZhuToolField(
        resolvedField: field,
      );
      expect(prompt, contains(method.label));
      expect(prompt, contains(method.path));
      expect(prompt, contains('2026-10-08T12:00'));
      expect(prompt, contains('不得补造穴位'));
      expect(prompt, contains('不得据此提供'));
      expect(prompt, contains('token 计数：UNKNOWN'));
      for (final other in methodCases.where((item) => item.path != method.path)) {
        expect(
          prompt,
          isNot(contains('【${other.label}】')),
          reason: '单方法字段上下文不能拼入其他方法：${other.path}',
        );
      }
    }
  });

  test('纳甲法 NOT_APPLICABLE 是可解释的原始状态，不补造穴位', () {
    // 2026-10-08 10:00：乙日巳时，本地引擎既无正开穴也无合日互用穴。
    final execution = ZiWuLiuZhuToolExecutor.executeWithSnapshot(
      unavailableNajiaArguments,
    );
    expect(execution.succeeded, isTrue);
    final snapshot = execution.structuredSnapshot!;
    final result = snapshot['result']! as Map<String, Object?>;
    final methods = result['methods']! as Map<String, Object?>;
    final najia = methods['naJia']! as Map<String, Object?>;

    expect(najia['status'], 'NOT_APPLICABLE');
    expect(najia.containsKey('point'), isFalse);
    expect(najia.containsKey('meridian'), isFalse);

    final ref = AiContextResolver.buildZiWuLiuZhuResultFieldContextRef(
      structuredSnapshot: snapshot,
      fieldPath: 'methods.naJia',
    );
    final resolution = AiContextResolver.resolveZiWuLiuZhuResultField(
      ref: ref,
      structuredSnapshot: snapshot,
    );
    expect(resolution.isResolved, isTrue);
    final prompt = AiContextPromptBuilder.buildZiWuLiuZhuToolField(
      resolvedField: resolution.value!,
    );
    expect(prompt, contains('NOT_APPLICABLE'));
    expect(prompt, contains('当前输入下没有对应开穴'));
    expect(prompt, contains('不得补造穴位'));
  });

  test('方法字段 Resolver 与 Prompt 对错源、错标题、过期、篡改和未知路径 fail closed', () {
    final execution =
        ZiWuLiuZhuToolExecutor.executeWithSnapshot(availableArguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildZiWuLiuZhuResultFieldContextRef(
      structuredSnapshot: snapshot,
      fieldPath: 'methods.naZi',
    );

    expect(
      () => AiContextResolver.buildZiWuLiuZhuResultFieldContextRef(
        structuredSnapshot: snapshot,
        fieldPath: 'methods.unsupported',
      ),
      throwsArgumentError,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:ziwuliuzhu',
      fieldPath: ref.fieldPath,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveZiWuLiuZhuResultField(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final wrongTitle = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      fieldPath: ref.fieldPath,
      title: '子午流注 · 飞腾八法',
    );
    expect(
      AiContextResolver.resolveZiWuLiuZhuResultField(
        ref: wrongTitle,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final staleVersion = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'ziwuliuzhu-engine@STALE',
      sourceId: ref.sourceId,
      fieldPath: ref.fieldPath,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveZiWuLiuZhuResultField(
        ref: staleVersion,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final result = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    );
    final methods = Map<String, Object?>.from(
      result['methods']! as Map<String, Object?>,
    );
    final naZi = Map<String, Object?>.from(
      methods['naZi']! as Map<String, Object?>,
    );
    naZi['benXue'] = '伪造穴位';
    methods['naZi'] = naZi;
    result['methods'] = methods;
    final altered = <String, Object?>{...snapshot, 'result': result};
    expect(
      AiContextResolver.resolveZiWuLiuZhuResultField(
        ref: ref,
        structuredSnapshot: altered,
      ).status,
      AiContextResolutionStatus.stale,
    );
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );
  });

  testWidgets('四个方法 Tab 在 402dp / 775dp 打开各自字段并恢复原滚动位置',
      (tester) async {
    addTearDown(tester.view.reset);

    final viewports = [
      (width: 402.0, height: 900.0, sidePanel: false),
      (width: 775.0, height: 1100.0, sidePanel: true),
    ];

    for (final viewport in viewports) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(viewport.width, viewport.height);
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            home: ZiWuLiuZhuScreen(
              key: ValueKey('ziwuliuzhu-${viewport.width}'),
              initialDate: DateTime(2026, 10, 8, 12),
              returnResultOnComplete: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < methodCases.length; index++) {
        final method = methodCases[index];
        final tab = find.descendant(
          of: find.byType(TabBar),
          matching: find.text(method.label),
        ).first;
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();

        final ask = find.byKey(
          ValueKey('ziwuliuzhu-method-ask-${method.key}'),
        );
        expect(
          ask,
          findsOneWidget,
          reason: '${method.label} 当前 Tab 必须展示独立字段级入口',
        );
        await tester.ensureVisible(ask);
        await tester.pumpAndSettle();

        final position = Scrollable.of(tester.element(ask)).position;
        final offsetBeforeOpen = position.pixels;

        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistantFinder = find.byType(LocalAiInterviewScreen);
        expect(assistantFinder, findsOneWidget);
        final assistant =
            tester.widget<LocalAiInterviewScreen>(assistantFinder);
        expect(assistant.initialMode, AssistantMode.tools);
        expect(assistant.contextualExplanationOnly, isTrue);
        expect(assistant.contextRef['kind'], 'field');
        expect(assistant.contextRef['moduleId'], 'ziwu_liuzhu');
        expect(assistant.contextRef['fieldPath'], method.path);
        expect(assistant.contextRef['snapshotId'], hasLength(64));
        expect(assistant.initialPrompt, contains(method.path));
        expect(assistant.initialPrompt, contains(method.label));
        expect(assistant.initialPrompt, contains('不得提供个体针刺'));
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistantFinder),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(find.byType(ZiWuLiuZhuScreen), findsOneWidget);
        expect(position.pixels, closeTo(offsetBeforeOpen, 0.5));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
