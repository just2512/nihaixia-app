import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/engine/bazi_twelve_stages.dart'
    show TwelveStageMode;
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/bazi_paipan_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/bazi_context_snapshot.dart';
import 'package:nihaisha_app/services/bazi_service.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';
import 'package:ziwei_core/ziwei_core.dart' show Location;

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const arguments = <String, String>{
    'birth_date': '1990-01-02',
    'birth_time': '08:30',
    'gender': 'male',
    'birthplace': '上海市',
  };

  Map<String, Object?> buildShanghaiSnapshot() {
    final solar = DateTime(1990, 1, 2, 8, 30);
    const location = Location(121.47, 31.23);
    const stageMode = TwelveStageMode.fireEarthSame;
    const useTrueSolarTime = true;
    const distinguishZiShi = false;
    final chart = computeBaZiPaipan(
      solar,
      isMale: true,
      useTrueSolarTime: useTrueSolarTime,
      twelveStageMode: stageMode,
      ratHourMode: distinguishZiShi,
      location: location,
    );
    final fortune = computeBaZiFortune(
      solar,
      isMale: true,
      location: location,
      ratHourMode: distinguishZiShi,
      useTrueSolarTime: useTrueSolarTime,
    );
    return BaziContextSnapshot.createFromCurrentResult(
      arguments: arguments,
      result: chart,
      fortune: fortune,
      locationMode: 'city-directory',
      locationLabel: '上海市',
      longitude: 121.47,
      latitude: 31.23,
      useTrueSolarTime: useTrueSolarTime,
      distinguishZiShi: distinguishZiShi,
      twelveStageMode: stageMode,
    );
  }

  test('Bazi snapshot preserves actual pillars, analysis, fortune and source provenance', () {
    final snapshot = buildShanghaiSnapshot();
    final input = snapshot['input']! as Map<String, Object?>;
    final location = input['location']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final pillars = result['pillars']! as Map<String, Object?>;
    final analysis = result['analysis']! as Map<String, Object?>;
    final fortune = result['fortune']! as Map<String, Object?>;

    expect(snapshot['capabilityId'], 'bazi');
    expect(snapshot['resultSchemaVersion'], BaziContextSnapshot.resultSchemaVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(snapshot['ruleVersion'], BaziContextSnapshot.ruleVersion);
    expect(snapshot['sourceIds'], containsAll([
      BaziContextSnapshot.sourceId,
      BaziContextSnapshot.citySourceId,
      'package:bazi_core@0.6.7',
      'package:sxwnl_spa_dart@0.18.5',
    ]));
    final argumentsSnapshot = Map<String, Object?>.from(
      input['arguments']! as Map,
    );
    expect(argumentsSnapshot['birth_date'], '1990-01-02');
    expect(location['mode'], 'city-directory');
    expect(location['label'], '上海市');
    expect(location['longitude'], 121.47);
    expect(location['latitude'], 31.23);
    expect(pillars['year'], isA<String>());
    expect(pillars['month'], isA<String>());
    expect(pillars['day'], isA<String>());
    expect(pillars['hour'], isA<String>());
    expect(pillars['gans'], hasLength(4));
    expect(pillars['zhis'], hasLength(4));
    expect((pillars['nayin']! as Map).keys,
        containsAll(['year', 'month', 'day', 'hour']));
    expect(result['tenGods'], hasLength(4));
    expect(result['hiddenTenGods'], hasLength(4));
    expect(analysis['dayMaster'], isA<String>());
    expect(analysis['strengthScore'], isA<double>());
    expect(analysis['fiveElements'], hasLength(5));
    expect(analysis['shensha'], isA<List<Object?>>());
    expect(fortune['decades'], hasLength(8));
    expect(snapshot['missingFields'], isEmpty);
    expect(snapshot['snapshotId'], hasLength(64));
    expect(AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
        snapshot['snapshotId']);

    final rebuilt = BaziContextSnapshot.rebuildFromInput(input: input);
    expect(rebuilt['snapshotId'], snapshot['snapshotId']);
    expect(rebuilt['result'], snapshot['result']);
  });

  test('Bazi resolver rejects stale rules, altered anchors, foreign sources and tampering', () {
    final snapshot = buildShanghaiSnapshot();
    final ref = AiContextResolver.buildBaziResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolved = AiContextResolver.resolveBaziToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'bazi');
    expect(ref.sourceId, BaziContextSnapshot.sourceId);
    expect(ref.snapshotId, snapshot['snapshotId']);
    expect(resolved.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildBaziToolResult(
      resolvedResult: resolved.value!,
    );
    expect(prompt, contains('八字排盘'));
    expect(prompt, contains('strengthScore'));
    expect(prompt, contains('不是概率'));
    expect(prompt, contains('不用于医疗'));

    AiContextRef alteredRef({
      String? anchor,
      String? source,
      String? rule,
    }) => AiContextRef(
          kind: AiContextKind.toolResult,
          moduleId: ref.moduleId,
          anchorId: anchor ?? ref.anchorId,
          anchorVersion: ref.anchorVersion,
          snapshotId: ref.snapshotId,
          ruleVersion: rule ?? ref.ruleVersion,
          sourceId: source ?? ref.sourceId,
          title: ref.title,
        );

    expect(
      AiContextResolver.resolveBaziToolResult(
        ref: alteredRef(rule: 'bazi-v1;STALE'),
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );
    expect(
      AiContextResolver.resolveBaziToolResult(
        ref: alteredRef(anchor: 'bazi:result:tampered'),
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );
    expect(
      AiContextResolver.resolveBaziToolResult(
        ref: alteredRef(source: 'unverified:bazi'),
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.unknown,
    );

    final tampered = Map<String, Object?>.from(snapshot);
    final result = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    );
    final pillars = Map<String, Object?>.from(
      result['pillars']! as Map<String, Object?>,
    )..['year'] = '甲子';
    result['pillars'] = pillars;
    tampered['result'] = result;
    expect(
      AiContextResolver.resolveBaziToolResult(
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

  test('Bazi default location is recorded as explicit engine default, not guessed city data', () {
    final solar = DateTime(1990, 1, 2, 8, 30);
    final chart = computeBaZiPaipan(solar, location: null);
    final fortune = computeBaZiFortune(solar, isMale: true, location: null);
    final snapshot = BaziContextSnapshot.createFromCurrentResult(
      arguments: const {
        'birth_date': '1990-01-02',
        'birth_time': '08:30',
        'gender': 'male',
        'birthplace': 'MISSING',
      },
      result: chart,
      fortune: fortune,
      locationMode: 'engine-default',
      locationLabel: null,
      longitude: 120,
      latitude: 30,
      useTrueSolarTime: true,
      distinguishZiShi: false,
      twelveStageMode: TwelveStageMode.fireEarthSame,
    );
    final input = snapshot['input']! as Map<String, Object?>;
    final location = input['location']! as Map<String, Object?>;

    expect(location['mode'], 'engine-default');
    expect(location['label'], 'MISSING');
    expect(
      () => BaziContextSnapshot.createFromCurrentResult(
        arguments: const {
          'birth_date': '1990-01-02',
          'birth_time': '08:30',
          'gender': 'male',
          'birthplace': 'MISSING',
        },
        result: chart,
        fortune: fortune,
        locationMode: 'engine-default',
        locationLabel: '旧城市标签',
        longitude: 120,
        latitude: 30,
        useTrueSolarTime: true,
        distinguishZiShi: false,
        twelveStageMode: TwelveStageMode.fireEarthSame,
      ),
      throwsArgumentError,
      reason: '未提供坐标时，旧城市名不得冒充本次排盘地点来源',
    );
    expect(snapshot['sourceIds'], contains(BaziContextSnapshot.defaultLocationSourceId));
    expect(snapshot['sourceIds'], isNot(contains(BaziContextSnapshot.citySourceId)));
    final ref = AiContextResolver.buildBaziResultContextRef(
      structuredSnapshot: snapshot,
    );
    expect(
      AiContextResolver.resolveBaziToolResult(
        ref: ref,
        structuredSnapshot: snapshot,
      ).isResolved,
      isTrue,
    );
  });

  test('Bazi field resolver binds one exact field to the immutable full-result snapshot', () {
    final snapshot = buildShanghaiSnapshot();
    final resultRef = AiContextResolver.buildBaziResultContextRef(
      structuredSnapshot: snapshot,
    );
    final fieldRef = AiContextResolver.buildBaziFieldContextRef(
      resultRef: resultRef,
      fieldPath: 'result.analysis.strengthScore',
      fieldLabel: '日主强弱分值',
    );
    final resolved = AiContextResolver.resolveBaziResultField(
      ref: fieldRef,
      structuredSnapshot: snapshot,
    );
    expect(resolved.isResolved, isTrue);
    expect(fieldRef.kind, AiContextKind.fieldValue);
    expect(fieldRef.moduleId, 'bazi');
    expect(fieldRef.snapshotId, snapshot['snapshotId']);
    expect(fieldRef.fieldPath, 'result.analysis.strengthScore');
    expect(resolved.value?.fieldValue.single['fieldPath'], fieldRef.fieldPath);
    expect(
      resolved.value?.fieldValue.single['value'],
      ((snapshot['result']! as Map<String, Object?>)['analysis']!
          as Map<String, Object?>)['strengthScore'],
    );
    expect(resolved.value?.fieldUnit, contains('不是概率'));

    final prompt = AiContextPromptBuilder.buildBaziToolField(
      resolvedField: resolved.value!,
    );
    expect(prompt, contains('result.analysis.strengthScore'));
    expect(prompt, contains('所属结果快照'));
    expect(prompt, contains('不是概率'));
    expect(prompt, contains('不用于医疗诊断'));

    final elementRef = AiContextResolver.buildBaziFieldContextRef(
      resultRef: resultRef,
      fieldPath: 'result.analysis.fiveElements.0.score',
      fieldLabel: '五行首项分值',
    );
    final elementResolved = AiContextResolver.resolveBaziResultField(
      ref: elementRef,
      structuredSnapshot: snapshot,
    );
    expect(elementResolved.isResolved, isTrue);
    expect(elementResolved.value?.ref.fieldPath, elementRef.fieldPath);

    final stale = AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: fieldRef.moduleId,
      anchorId: fieldRef.anchorId,
      anchorVersion: fieldRef.anchorVersion,
      snapshotId: fieldRef.snapshotId,
      ruleVersion: 'bazi-v1;STALE',
      sourceId: fieldRef.sourceId,
      fieldPath: fieldRef.fieldPath,
      title: fieldRef.title,
    );
    expect(
      AiContextResolver.resolveBaziResultField(
        ref: stale,
        structuredSnapshot: snapshot,
      ).status,
      AiContextResolutionStatus.stale,
    );

    final tampered = Map<String, Object?>.from(snapshot);
    final result = Map<String, Object?>.from(
      snapshot['result']! as Map<String, Object?>,
    );
    final analysis = Map<String, Object?>.from(
      result['analysis']! as Map<String, Object?>,
    )..['strengthScore'] = -999.0;
    result['analysis'] = analysis;
    tampered['result'] = result;
    expect(
      AiContextResolver.resolveBaziResultField(
        ref: fieldRef,
        structuredSnapshot: tampered,
      ).status,
      AiContextResolutionStatus.stale,
    );
    expect(
      () => AiContextResolver.buildBaziFieldContextRef(
        resultRef: resultRef,
        fieldPath: 'result.analysis.untrustedField',
        fieldLabel: '不支持字段',
      ),
      throwsArgumentError,
    );
  });

  testWidgets('Bazi strength field opens a field-bound contextual assistant', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 1400);
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
          home: BaZiPaipanScreen(
            initialSolar: DateTime(1990, 1, 2, 8, 30),
            initialIsMale: true,
            initialCityName: '上海市',
            initialLng: 121.47,
            initialLat: 31.23,
          ),
        ),
      ),
        );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('八字详批'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final fieldAsk = find.byKey(const ValueKey('bazi-field-strength'));
    expect(fieldAsk, findsOneWidget);
    await tester.tap(fieldAsk);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final assistant = find.byType(LocalAiInterviewScreen);
    expect(assistant, findsOneWidget);
    final widget = tester.widget<LocalAiInterviewScreen>(assistant);
    expect(widget.initialMode, AssistantMode.tools);
    expect(widget.contextualExplanationOnly, isTrue);
    expect(widget.contextRef['kind'], 'field');
    expect(widget.contextRef['moduleId'], 'bazi');
    expect(
      widget.contextRef['fieldPath'],
      'result.analysis.strengthScore',
    );
    expect(widget.contextRef['snapshotId'], hasLength(64));
    expect(widget.initialPrompt, contains('strengthScore'));
    expect(widget.initialPrompt, contains('不是概率'));
    expect(widget.initialPrompt, contains('日主强弱分值'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bazi result exposes contextual Ask AI and opens the tools assistant', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 1200);
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
          home: BaZiPaipanScreen(
            initialSolar: DateTime(1990, 1, 2, 8, 30),
            initialIsMale: true,
            initialCityName: '上海市',
            initialLng: 121.47,
            initialLat: 31.23,
          ),
        ),
      ),
        );
    await tester.pumpAndSettle();

    final ask = find.text('问 AI 解读当前八字排盘');
    expect(ask, findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    // Editing the form alone does not change the chart already rendered above.
    // The contextual prompt must stay bound to the previously executed result.
    await tester.tap(find.text('女').last);
    await tester.pump();

    await tester.ensureVisible(ask);
    await tester.pumpAndSettle();
    await tester.tap(ask);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final assistant = find.byType(LocalAiInterviewScreen);
    expect(assistant, findsOneWidget);
    final widget = tester.widget<LocalAiInterviewScreen>(assistant);
    expect(widget.initialMode, AssistantMode.tools);
    expect(widget.contextualExplanationOnly, isTrue);
    expect(widget.contextRef['kind'], 'toolResult');
    expect(widget.contextRef['moduleId'], 'bazi');
    expect(widget.contextRef['snapshotId'], hasLength(64));
    expect(widget.initialPrompt, contains('八字排盘'));
    expect(widget.initialPrompt, contains('strengthScore'));
    expect(widget.initialPrompt, contains('"gender":"male"'));
    expect(widget.initialPrompt, isNot(contains('"gender":"female"')));
    expect(tester.takeException(), isNull);
  });
}
