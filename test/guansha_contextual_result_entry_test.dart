import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/guansha_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/guansha_result_context_executor.dart';
import 'package:nihaisha_app/services/guansha_tool_executor.dart';
import 'package:nihaisha_app/widgets/bazi_location_picker.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.configureTestDatabase(
      'guansha_contextual_result_test.db',
      factory: databaseFactoryFfi,
    );
    final settings = SettingsRepository.instance;
    if (!settings.isLoaded) await settings.load();
  });

  tearDownAll(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  const arguments = <String, String>{
    'birth_date': '1990-01-02',
    'birth_time': '08:30',
    'gender': 'male',
    'birthplace': '上海市',
  };

  test('小儿关煞上下文快照绑定本地规则、城市目录和实际历法设置', () async {
    final execution =
        await GuanshaResultContextExecutor.executeWithSnapshot(arguments);

    expect(
      execution.succeeded,
      isTrue,
      reason: execution.result.toConversationText(),
    );
    expect(execution.result.validateFor('guansha'), isEmpty);
    expect(execution.result.validateArgumentsMatch(arguments), isEmpty);
    expect(execution.result.sourceIds, const [
      GuanshaToolExecutor.sourceId,
      GuanshaToolExecutor.dataSourceId,
      GuanshaToolExecutor.locationSourceId,
    ]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], GuanshaResultContextExecutor.moduleId);
    expect(
      snapshot['resultSchemaVersion'],
      GuanshaResultContextExecutor.resultSchemaVersion,
    );
    expect(snapshot['ruleVersion'], GuanshaResultContextExecutor.ruleVersion);
    expect(
      GuanshaResultContextExecutor.ruleVersion
          .split(';')
          .where((entry) => entry.contains('-blob@'))
          .every(
            (entry) => entry.substring(entry.indexOf('@') + 1).length == 40,
          ),
      isTrue,
    );
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input['method'], 'explicitBirthDetails');
    expect(input['arguments'], arguments);
    expect(input['settings'], isA<Map<String, Object?>>());
    expect(values['出生公历'], isNotEmpty);
    expect(values['性别'], '男');
    expect(values['出生地点'], contains('上海'));
    expect(values['出生地坐标'], contains('东经'));
    expect(values['出生农历'], isNotEmpty);
    expect(values['四柱'], isNotEmpty);
    expect(values['关煞命中数量'], isNotEmpty);
    expect(values['本地规则结果'], isNotEmpty);
    expect(values['规则库范围'], contains('36 关与 18 条扩展煞'));
    expect(snapshot['privacy'], {
      'childBirthDetails': 'LOCAL_VERIFICATION_ONLY',
      'modelPromptPolicy': 'REDACT_EXACT_CHILD_BIRTH_DETAILS',
    });
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );

    final repeated =
        await GuanshaResultContextExecutor.executeWithSnapshot(arguments);
    expect(
      repeated.structuredSnapshot!['snapshotId'],
      snapshot['snapshotId'],
    );
  });

  test('Resolver 与 Prompt 精确回链，模型上下文不包含儿童生辰和身份资料', () async {
    final execution =
        await GuanshaResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildGuanshaResultContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveGuanshaToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'guansha');
    expect(ref.sourceId, GuanshaToolExecutor.sourceId);
    expect(ref.anchorId, contains('guansha:result:'));
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      structuredSnapshot: resolution.value!.structuredSnapshot,
    );
    final values = (snapshot['result']! as Map<String, Object?>)['values']!
        as Map<String, Object?>;
    expect(prompt, contains('REDACTED_LOCAL_ONLY'));
    expect(prompt, isNot(contains(arguments['birth_date']!)));
    expect(prompt, isNot(contains(arguments['birth_time']!)));
    expect(prompt, isNot(contains(arguments['gender']!)));
    expect(prompt, isNot(contains(arguments['birthplace']!)));
    for (final field in ['出生公历', '性别', '出生地点', '出生地坐标', '出生农历', '四柱']) {
      expect(
        prompt,
        isNot(contains('"$field":"${values[field]}"')),
      );
    }
    expect(prompt, contains('小儿关煞结果仅是 App 本地收录的传统民俗规则命中记录'));
    expect(prompt, contains('不得根据关煞名称、部位或传统说法推断疾病'));
    expect(prompt, contains('不得建议或暗示购买法事'));
  });

  test('Resolver 对错源、篡改快照和不完整输入 fail closed', () async {
    final execution =
        await GuanshaResultContextExecutor.executeWithSnapshot(arguments);
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildGuanshaResultContextRef(
      structuredSnapshot: snapshot,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:guansha',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveGuanshaToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      )).status,
      AiContextResolutionStatus.unknown,
    );
    expect(
      () => AiContextPromptBuilder.buildToolResult(
        ref: wrongSource,
        structuredSnapshot: snapshot,
      ),
      throwsArgumentError,
    );

    final tampered = <String, Object?>{
      ...snapshot,
      'result': <String, Object?>{
        ...(snapshot['result']! as Map<String, Object?>),
        'values': <String, Object?>{
          ...((snapshot['result']! as Map<String, Object?>)['values']!
              as Map<String, Object?>),
          '关煞命中数量': '999',
        },
      },
    };
    expect(
      (await AiContextResolver.resolveGuanshaToolResult(
        ref: ref,
        structuredSnapshot: tampered,
      )).status,
      AiContextResolutionStatus.stale,
    );

    expect(
      () => AiContextResolver.buildGuanshaResultContextRef(
        structuredSnapshot: {
          ...snapshot,
          'sourceIds': const ['unverified:guansha'],
        },
      ),
      throwsArgumentError,
    );
  });

  testWidgets('窄屏和宽屏：选择唯一城市、测算后才开放已脱敏的情境问 AI',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final viewport in [const Size(402, 880), const Size(775, 1024)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: const MaterialApp(
            home: GuanshaScreen(returnResultOnComplete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ask = find.text('问 AI 解读本次关煞结果');
      expect(ask, findsNothing);

      final locationRow = find.byType(BaZiLocationRow);
      await tester.ensureVisible(locationRow);
      await tester.tap(locationRow);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '上海市');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('上海市').last);
      await tester.pumpAndSettle();

      final calculate = find.text('测算关煞');
      await tester.ensureVisible(calculate);
      await tester.tap(calculate);
      await tester.pumpAndSettle();

      await tester.ensureVisible(ask);
      expect(ask, findsOneWidget);
      expect(find.text('将本次关煞结果带回助手对话'), findsOneWidget);
      final askButton = tester.widget<FilledButton>(
        find.ancestor(of: ask, matching: find.byType(FilledButton)).first,
      );
      expect(askButton.onPressed, isNotNull);
      await tester.tap(ask);
      await tester.pumpAndSettle();

      expect(find.text('确认本次小儿关煞结果输入'), findsOneWidget);
      await tester.tap(find.text('确认并解读'));
      await tester.pumpAndSettle();

      final ai = tester.widget<LocalAiInterviewScreen>(
        find.byType(LocalAiInterviewScreen),
      );
      expect(ai.contextRef['moduleId'], 'guansha');
      expect(ai.contextualExplanationOnly, isTrue);
      expect(ai.initialPrompt, contains('REDACTED_LOCAL_ONLY'));
      expect(ai.initialPrompt, isNot(contains('上海市')));
      expect(ai.initialPrompt, contains('出生地点'));
      expect(ai.initialPrompt, isNot(contains('上海市')));
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
