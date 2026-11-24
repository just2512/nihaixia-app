import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/allow_context_authorizer.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/dosage_converter_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/dosage_result_context_executor.dart';
import 'package:nihaisha_app/services/dosage_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('重量换算快照严格对应 App 结果和双重来源', () async {
    const arguments = {
      'value': '1',
      'unit': '两',
      'standard': 'han',
    };
    final execution = DosageResultContextExecutor.executeWithSnapshot(
      arguments: arguments,
    );

    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('dosage'), isEmpty);
    expect(execution.result.validateArgumentsMatch(arguments), isEmpty);
    expect(execution.result.values['换算结果'], '15.625');
    expect(execution.result.values['目标单位'], '克');
    expect(execution.result.sourceIds, [
      DosageToolExecutor.sourceId,
      DosageToolExecutor.factorsSourceId,
    ]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'dosage');
    expect(
      snapshot['resultSchemaVersion'],
      DosageResultContextExecutor.resultSchemaVersion,
    );
    expect(snapshot['ruleVersion'], DosageResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input['method'], 'explicitUnitConversion');
    expect(input['arguments'], arguments);
    expect(values['换算结果'], '15.625');
    expect(values['业务范围'], '仅单位换算；不计算药物处方剂量');
    expect(snapshot['missingFields'], isEmpty);
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );
  });

  test('容量和长度仍调用同一 App 转换器，不借用重量标准换算', () {
    for (final entry in [
      ('升', '200', '毫升'),
      ('尺', '23.1', '厘米'),
    ]) {
      final execution = DosageResultContextExecutor.executeWithSnapshot(
        arguments: {
          'value': '1',
          'unit': entry.$1,
          'standard': 'han',
        },
      );
      expect(execution.succeeded, isTrue);
      final values =
          (execution.structuredSnapshot!['result']! as Map<String, Object?>)
              ['values']! as Map<String, Object?>;
      expect(values['换算结果'], entry.$2);
      expect(values['目标单位'], entry.$3);
    }
  });

  test('Resolver 与 Prompt 严格绑定引擎、常数、输入和快照', () async {
    const arguments = {
      'value': '2',
      'unit': '两',
      'standard': 'han',
    };
    final execution = DosageResultContextExecutor.executeWithSnapshot(
      arguments: arguments,
    );
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildDosageResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveDosageToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'dosage');
    expect(ref.sourceId, DosageToolExecutor.sourceId);
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      structuredSnapshot: resolution.value!.structuredSnapshot,
    );
    expect(prompt, contains('31.25'));
    expect(prompt, contains('不计算药物处方剂量'));
    expect(prompt, contains('不得重新换算'));
    expect(prompt, contains('不得把单位换算结果说成推荐剂量'));
    expect(prompt, isNot(contains('胖子：五钱起')));
    expect(prompt, isNot(contains('特殊药物容积→重量')));
  });

  test('Resolver 拒绝错误来源、过期规则和被篡改的换算值', () async {
    final execution = DosageResultContextExecutor.executeWithSnapshot(
      arguments: const {'value': '1', 'unit': '两', 'standard': 'han'},
    );
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildDosageResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'local-engine:untrusted-converter',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveDosageToolResult(
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
      ruleVersion: 'dosage@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveDosageToolResult(
        ref: staleRule,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.stale,
    );

    final changedResult = Map<String, Object?>.from(snapshot['result']! as Map);
    final changedValues =
        Map<String, Object?>.from(changedResult['values']! as Map);
    changedValues['换算结果'] = '999';
    changedResult['values'] = changedValues;
    final tampered = {...snapshot, 'result': changedResult};
    expect(
      (await AiContextResolver.resolveDosageToolResult(
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

  test('输入无效或参数超出声明范围时不生成上下文快照', () {
    final invalid = DosageResultContextExecutor.executeWithSnapshot(
      arguments: const {'value': '-1', 'unit': '两', 'standard': 'han'},
    );
    expect(invalid.succeeded, isFalse);
    expect(invalid.structuredSnapshot, isNull);

    final extra = DosageResultContextExecutor.executeWithSnapshot(
      arguments: const {
        'value': '1',
        'unit': '两',
        'standard': 'han',
        'dose_advice': '请给药',
      },
    );
    expect(extra.succeeded, isFalse);
    expect(extra.structuredSnapshot, isNull);
  });

  for (final viewport in [
    (width: 402.0, height: 880.0, isSidePanel: false),
    (width: 775.0, height: 1100.0, isSidePanel: true),
  ]) {
    testWidgets(
      '度量衡换算页面在 ${viewport.width.toInt()}dp 将当前换算结果带入情境助手',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(viewport.width, viewport.height);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          TestAuthorizedFeatureScope(
            child: ContextualAiConversationStoreScope(
            conversationStore: InMemoryAssistantConversationStore(),
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: AppColors.colorSchemeFor(Brightness.light),
                extensions: [AppColors.light],
              ),
              home: const DosageConverterScreen(),
            ),
          )
          ),
        );
        await tester.pumpAndSettle();

        final ask = find.text('问 AI 解释当前换算');
        await tester.ensureVisible(ask);
        expect(ask, findsOneWidget);
        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final widget = tester.widget<LocalAiInterviewScreen>(assistant);
        expect(widget.initialMode, AssistantMode.tools);
        expect(widget.contextualExplanationOnly, isTrue);
        expect(widget.contextRef['kind'], 'toolResult');
        expect(widget.contextRef['moduleId'], 'dosage');
        expect(widget.contextRef['snapshotId'], hasLength(64));
        expect(widget.contextRef['sourceId'], DosageToolExecutor.sourceId);
        expect(widget.initialPrompt, contains('15.625'));
        expect(widget.initialPrompt, contains('不得把单位换算结果说成推荐剂量'));
        expect(widget.initialPrompt, isNot(contains('小孩：半钱')));
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(assistant), rootNavigator: true).pop();
        await tester.pumpAndSettle();
        expect(find.byType(DosageConverterScreen), findsOneWidget);
        expect(ask, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
