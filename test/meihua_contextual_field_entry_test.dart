import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sensors_plus/sensors_plus.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/meihua_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/meihua_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 11, 18, 12);

  test('Meihua field resolver binds a scalar path to the exact immutable parent snapshot', () {
    final execution = MeihuaToolExecutor.executeWithSnapshot(
      const {
        'method': 'number',
        'date': '2026-11-18',
        'first': '3',
        'second': '7',
      },
      now: fixedNow,
    );
    expect(execution.succeeded, isTrue);
    final snapshot = execution.structuredSnapshot!;
    final resultRef = AiContextResolver.buildMeihuaResultContextRef(
      structuredSnapshot: snapshot,
    );
    final fieldRef = AiContextResolver.buildMeihuaFieldContextRef(
      resultRef: resultRef,
      fieldPath: 'result.main.name',
      fieldLabel: '主卦名称',
    );
    final resolved = AiContextResolver.resolveMeihuaResultField(
      ref: fieldRef,
      structuredSnapshot: snapshot,
    );
    final result = snapshot['result']! as Map<String, Object?>;
    final main = result['main']! as Map<String, Object?>;
    expect(resolved.isResolved, isTrue);
    expect(fieldRef.kind, AiContextKind.fieldValue);
    expect(fieldRef.moduleId, 'meihua');
    expect(fieldRef.snapshotId, snapshot['snapshotId']);
    expect(fieldRef.fieldPath, 'result.main.name');
    expect(resolved.value?.fieldValue.single['value'], main['name']);
    expect(resolved.value?.structuredSnapshot['snapshotId'], snapshot['snapshotId']);

    final prompt = AiContextPromptBuilder.buildMeihuaToolField(
      resolvedField: resolved.value!,
    );
    expect(prompt, contains('result.main.name'));
    expect(prompt, contains('主卦名称'));
    expect(prompt, contains('不得重新起卦'));
    expect(prompt, contains('不是科学预测'));

    final relationRef = AiContextResolver.buildMeihuaFieldContextRef(
      resultRef: resultRef,
      fieldPath: 'result.mainRelation.label',
      fieldLabel: '体用关系',
    );
    expect(
      AiContextResolver.resolveMeihuaResultField(
        ref: relationRef,
        structuredSnapshot: snapshot,
      ).isResolved,
      isTrue,
    );

    final stageRef = AiContextResolver.buildMeihuaFieldContextRef(
      resultRef: resultRef,
      fieldPath: 'result.stages.0.detail',
      fieldLabel: '主阶段推演',
    );
    expect(
      AiContextResolver.resolveMeihuaResultField(
        ref: stageRef,
        structuredSnapshot: snapshot,
      ).isResolved,
      isTrue,
    );

    expect(
      () => AiContextResolver.buildMeihuaFieldContextRef(
        resultRef: resultRef,
        fieldPath: 'result.input.untrusted',
        fieldLabel: '不支持路径',
      ),
      throwsArgumentError,
    );
  });

  test('Meihua field resolver rejects stale rules and tampered result snapshots', () {
    final execution = MeihuaToolExecutor.executeWithSnapshot(
      const {
        'method': 'number',
        'date': '2026-11-18',
        'first': '3',
        'second': '7',
      },
      now: fixedNow,
    );
    final snapshot = execution.structuredSnapshot!;
    final resultRef = AiContextResolver.buildMeihuaResultContextRef(
      structuredSnapshot: snapshot,
    );
    final fieldRef = AiContextResolver.buildMeihuaFieldContextRef(
      resultRef: resultRef,
      fieldPath: 'result.movingYao',
      fieldLabel: '动爻位置',
    );
    final stale = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: fieldRef.moduleId,
      anchorId: fieldRef.anchorId,
      anchorVersion: fieldRef.anchorVersion,
      snapshotId: fieldRef.snapshotId,
      ruleVersion: 'meihua-engine@STALE',
      sourceId: fieldRef.sourceId,
      fieldPath: fieldRef.fieldPath,
      title: fieldRef.title,
    );
    expect(
      AiContextResolver.resolveMeihuaResultField(
        ref: stale,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final tampered = Map<String, Object?>.from(snapshot);
    final result = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    )..['movingYao'] = 99;
    tampered['result'] = result;
    expect(
      AiContextResolver.resolveMeihuaResultField(
        ref: fieldRef,
        structuredSnapshot: tampered,
      ).status,
      AiContextResolutionStatus.stale,
    );
  });

  testWidgets('Meihua field entry opens a field-bound explanation-only assistant', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 3200);
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
          home: MeihuaScreen(
            accelSource: ({
              Duration samplingPeriod = Duration.zero,
            }) => const Stream<AccelerometerEvent>.empty(),
          ),
        ),
      ),
        );
    await tester.pumpAndSettle();

    final ask = find.byKey(const ValueKey('meihua-field-main'));
    expect(ask, findsOneWidget);
    await tester.ensureVisible(ask);
    await tester.pumpAndSettle();
    await tester.tap(ask);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final assistant = find.byType(LocalAiInterviewScreen);
    expect(assistant, findsOneWidget);
    final widget = tester.widget<LocalAiInterviewScreen>(assistant);
    expect(widget.initialMode, AssistantMode.metaphysics);
    expect(widget.contextualExplanationOnly, isTrue);
    expect(widget.contextRef['kind'], 'field');
    expect(widget.contextRef['moduleId'], 'meihua');
    expect(widget.contextRef['fieldPath'], 'result.main.name');
    expect(widget.contextRef['snapshotId'], hasLength(64));
    expect(widget.initialPrompt, contains('主卦名称'));
    expect(widget.initialPrompt, contains('不得重新起卦'));
    expect(tester.takeException(), isNull);
  });
}
