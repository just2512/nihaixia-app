import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/yunqi_tool_executor.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final selectedDate = DateTime(2026, 11, 18);
  const paths = <String>[
    'chart.wuxing',
    'chart.wuyun',
    'chart.liuqi',
  ];
  const tabLabels = <String>[
    '运气五行图',
    '五运图',
    '六气图',
  ];

  test('three YunQi charts resolve to separate allowlisted values from one annual snapshot', () {
    final snapshot = YunQiToolExecutor.createStructuredSnapshot(selectedDate);
    final result = snapshot['result']! as Map<String, Object?>;
    final annual = result['annualData']! as Map<String, Object?>;

    for (final path in paths) {
      final ref = AiContextResolver.buildYunqiChartFieldContextRef(
        structuredSnapshot: snapshot,
        fieldPath: path,
      );
      final resolution = AiContextResolver.resolveYunqiChartField(
        ref: ref,
        structuredSnapshot: snapshot,
      );

      expect(ref.kind, AiContextKind.fieldValue);
      expect(ref.moduleId, 'yunqi');
      expect(ref.fieldPath, path);
      expect(ref.snapshotId, snapshot['snapshotId']);
      expect(ref.sourceId, YunQiToolExecutor.sourceId);
      expect(resolution.isResolved, isTrue, reason: path);

      final field = resolution.value!;
      expect(field.fieldValue, hasLength(1));
      expect(field.fieldValue.single['fieldPath'], path);
      expect(
        field.fieldValue.single['unit'],
        field.fieldUnit,
      );
      expect(field.structuredSnapshot['snapshotId'], snapshot['snapshotId']);

      final selected = field.fieldValue.single['value']! as Map<String, Object?>;
      switch (path) {
        case 'chart.wuxing':
          final yearProperties =
              selected['yearProperties']! as Map<String, Object?>;
          expect(yearProperties['yun'], annual['yun']);
          expect(yearProperties['taiGuo'], annual['taiGuo']);
          expect(yearProperties['siTian'], annual['siTian']);
          expect(yearProperties['siTianWx'], annual['siTianWx']);
          expect(yearProperties['zaiQuan'], annual['zaiQuan']);
          expect(selected['selectedStep'], isA<Map>());
          expect(selected['mainYun'], annual['mainYun']);
          expect(selected['guestYun'], annual['guestYun']);
          expect(selected['mainQi'], annual['mainQi']);
          expect(selected['guestQi'], annual['guestQi']);
          expect(selected['hostGuestRelations'], annual['hostGuestRelations']);
          break;
        case 'chart.wuyun':
          expect(selected['mainYun'], annual['mainYun']);
          expect(selected['guestYun'], annual['guestYun']);
          expect(selected.containsKey('mainQi'), isFalse);
          expect(selected['selectedStep'], isA<Map>());
          break;
        case 'chart.liuqi':
          expect(selected['mainQi'], annual['mainQi']);
          expect(selected['guestQi'], annual['guestQi']);
          expect(selected['hostGuestRelations'], annual['hostGuestRelations']);
          expect(selected.containsKey('mainYun'), isFalse);
          break;
      }

      final prompt = AiContextPromptBuilder.buildYunqiChartField(
        resolvedField: field,
      );
      expect(prompt, contains(path));
      expect(prompt, contains('2026-11-18'));
      expect(prompt, contains('不是'));
      expect(prompt, contains('不得提供个体医疗诊断'));
      expect(prompt, contains('token 计数：UNKNOWN'));
    }
  });

  test('YunQi chart resolver rejects unsupported, stale, altered and wrong-source refs', () {
    final snapshot = YunQiToolExecutor.createStructuredSnapshot(selectedDate);
    final ref = AiContextResolver.buildYunqiChartFieldContextRef(
      structuredSnapshot: snapshot,
      fieldPath: 'chart.wuyun',
    );

    expect(
      () => AiContextResolver.buildYunqiChartFieldContextRef(
        structuredSnapshot: snapshot,
        fieldPath: 'chart.unsupported',
      ),
      throwsArgumentError,
    );

    final staleRef = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'yunqi-engine@STALE',
      sourceId: ref.sourceId,
      fieldPath: ref.fieldPath,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYunqiChartField(
        ref: staleRef,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:yunqi',
      fieldPath: ref.fieldPath,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYunqiChartField(
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
      title: '六气图',
    );
    expect(
      AiContextResolver.resolveYunqiChartField(
        ref: wrongTitle,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final alteredResult = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    );
    final alteredAnnual = Map<String, Object?>.from(
      alteredResult['annualData']! as Map<String, Object?>,
    );
    alteredAnnual['mainYun'] = const <Object?>[];
    alteredResult['annualData'] = alteredAnnual;
    final alteredSnapshot = <String, Object?>{
      ...snapshot,
      'result': alteredResult,
    };
    expect(
      AiContextResolver.resolveYunqiChartField(
        ref: ref,
        structuredSnapshot: alteredSnapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final alteredDigest = Map<String, Object?>.from(snapshot)
      ..['snapshotId'] =
          '0000000000000000000000000000000000000000000000000000000000000000';
    final alteredDigestRef = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId.replaceFirst(
        ref.snapshotId!,
        alteredDigest['snapshotId']! as String,
      ),
      anchorVersion: alteredDigest['snapshotId']! as String,
      snapshotId: alteredDigest['snapshotId']! as String,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      fieldPath: ref.fieldPath,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYunqiChartField(
        ref: alteredDigestRef,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    expect(
      AiContextResolver.resolveYunqiChartField(
        ref: ref,
        structuredSnapshot: {
          ...snapshot,
          'sourceIds': const <String>['unverified:source'],
        },
      ).status,
      AiContextResolutionStatus.stale,
    );
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );
  });

  testWidgets('each chart tab opens its own contextual field and restores page scroll at 402dp and 775dp', (tester) async {
    addTearDown(tester.view.reset);

    for (final width in [402.0, 775.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 2400);
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            home: YunQiScreen(key: ValueKey('yunqi-$width'), initialDate: selectedDate),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageScrollable = find.descendant(
        of: find.byType(YunQiScreen),
        matching: find.byType(Scrollable),
      ).first;
      final pagePosition =
          tester.state<ScrollableState>(pageScrollable).position;

      for (var tabIndex = 0; tabIndex < paths.length; tabIndex++) {
        if (pagePosition.pixels > pagePosition.minScrollExtent) {
          pagePosition.jumpTo(pagePosition.minScrollExtent);
          await tester.pumpAndSettle();
        }
        final tab = find.text(tabLabels[tabIndex]).first;
        await tester.tap(tab);
        await tester.pumpAndSettle();

        final ask = find.byKey(const ValueKey('yunqi-chart-field-ask'));
        await tester.ensureVisible(ask);
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byType(YunQiScreen),
          matching: find.byType(Scrollable),
        ).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        final beforeOpen = position.pixels;

        await tester.tap(ask);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistantFinder = find.byType(LocalAiInterviewScreen);
        expect(assistantFinder, findsOneWidget);
        final assistant = tester.widget<LocalAiInterviewScreen>(assistantFinder);
        expect(assistant.contextRef['kind'], 'field');
        expect(assistant.contextRef['moduleId'], 'yunqi');
        expect(assistant.contextRef['fieldPath'], paths[tabIndex]);
        expect(assistant.contextRef['snapshotId'], hasLength(64));
        expect(assistant.initialMode, AssistantMode.tools);
        expect(assistant.contextualExplanationOnly, isTrue);
        expect(assistant.initialPrompt, contains(paths[tabIndex]));
        expect(assistant.initialPrompt, contains(tabLabels[tabIndex]));
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistantFinder),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(find.byType(YunQiScreen), findsOneWidget);
        expect(position.pixels, closeTo(beforeOpen, 0.5));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
