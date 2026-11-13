import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/yijing_engine.dart';
import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
import 'package:nihaisha_app/screens/yijing_result_screen.dart';
import 'package:nihaisha_app/screens/yijing_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/bazi_paipan_screen.dart';
import 'package:nihaisha_app/screens/chenggu_bone_screen.dart';
import 'package:nihaisha_app/screens/guansha_screen.dart';
import 'package:nihaisha_app/screens/shousheng_debt_screen.dart';
import 'package:nihaisha_app/screens/huangdi_siji_screen.dart';
import 'package:nihaisha_app/screens/sanshan_lingqian_screen.dart';
import 'package:nihaisha_app/screens/ziwei_chart_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';


const _readyStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: true,
  modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'litert',
);

class _NoLostImagePicker implements LocalAiImagePicker {
  @override
  Future<String?> pickCameraImagePath() async => null;

  @override
  Future<String?> pickGalleryImagePath() async => null;

  @override
  Future<String?> retrieveLostImagePath() async => null;
}

class _NoopAssistantConversationStore implements AssistantConversationStore {
  final savedMessages = <Map<String, Object?>>[];

  @override
  Future<int> createAssistantConversation({
    String title = '新对话',
    String mode = 'general',
  }) async => 1;

  @override
  Future<int> saveAssistantMessage({
    required int conversationId,
    required String role,
    required String content,
    String? metadata,
  }) async {
    savedMessages.add({
      'conversationId': conversationId,
      'role': role,
      'content': content,
      'metadata': metadata,
    });
    return savedMessages.length;
  }

  @override
  Future<int> saveAssistantTurn({
    required int conversationId,
    String? userContent,
    String? userMetadata,
    required String assistantContent,
    String? assistantMetadata,
  }) async {
    if (userContent != null && userContent.trim().isNotEmpty) {
      await saveAssistantMessage(
        conversationId: conversationId,
        role: 'user',
        content: userContent,
        metadata: userMetadata,
      );
    }
    return saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: assistantContent,
      metadata: assistantMetadata,
    );
  }

  @override
  Future<List<int>> saveAssistantMessagesAtomically({
    required int conversationId,
    required List<AssistantMessageDraft> messages,
  }) async {
    final ids = <int>[];
    for (final message in messages) {
      ids.add(await saveAssistantMessage(
        conversationId: conversationId,
        role: message.role,
        content: message.content,
        metadata: message.metadata,
      ));
    }
    return ids;
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  }) async => const [];

  @override
  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  }) async => const [];

  @override
  Future<void> saveTcmInterviewTaskState({
    required int conversationId,
    required TcmInterviewTaskState state,
  }) async {}

  @override
  Future<TcmInterviewTaskState?> getTcmInterviewTaskState({
    required int conversationId,
  }) async => null;

  @override
  Future<void> deleteAssistantConversations(List<int> conversationIds) async {}
}

class _RecordingAssistantService extends LocalAiService {
  String? restoredTranscript;
  List<String> restoredUserMessages = const [];
  final sentTexts = <String>[];
  final sentContexts = <String>[];
  int modelCalls = 0;

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

  @override
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
  }) async {
    modelCalls++;
    sentTexts.add(text);
    sentContexts.add(context);
    return '已收到：$text';
  }

  @override
  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
  }) async {
    restoredTranscript = transcript;
    restoredUserMessages = List<String>.from(userMessages);
  }
}

Future<void> _waitForText(WidgetTester tester, String value) async {
  final finder = find.text(value);
  for (var attempt = 0; attempt < 50 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget, reason: '等待页面元素超时：$value');
}

Future<void> _scrollUntilTextVisible(WidgetTester tester, String value) async {
  final finder = find.text(value);
  final verticalScrollables = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  expect(verticalScrollables, findsWidgets);
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: verticalScrollables.first,
  );
  expect(finder, findsOneWidget, reason: '结果卡片未出现：$value');
}

void main() {
  testWidgets('五运六气工具可把实际推算结果返回统一助手', (tester) async {
    Object? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned = await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const YunQiScreen(returnResultOnComplete: true),
                  ),
                );
              },
              child: const Text('打开五运六气'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开五运六气'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('将本次推算结果带回助手对话'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('将本次推算结果带回助手对话'), findsOneWidget);

    await tester.tap(find.text('将本次推算结果带回助手对话'));
    await tester.pumpAndSettle();

    expect(returned, isA<AssistantToolResult>());
    final result = returned! as AssistantToolResult;
    expect(result.toolId, 'yunqi');
    expect(result.title, '五运六气推算');
    expect(result.values['推算日期'], isNotEmpty);
    expect(result.values['岁运'], isNotEmpty);
    expect(result.values['司天'], isNotEmpty);
    expect(result.values['在泉'], isNotEmpty);
    expect(result.disclaimer, contains('仅供理论学习'));
    expect(result.toConversationText().split('\n').length, greaterThan(2));
    expect(result.toConversationText(), isNot(contains(r'\n')));
    expect(tester.takeException(), isNull);
  });


  testWidgets('五运六气结果回到统一时间线并同步进本地模型上下文', (tester) async {
    final service = _RecordingAssistantService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _NoopAssistantConversationStore(),
          imagePicker: _NoLostImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我推算五运六气');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.text('打开五运六气推算'), findsOneWidget);

    await tester.tap(find.text('打开五运六气推算'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('将本次推算结果带回助手对话'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('将本次推算结果带回助手对话'));
    await tester.pumpAndSettle();

    final returnedToolResult = find.byWidgetPredicate(
      (widget) => widget is SelectableText &&
          (widget.data ?? '').contains('五运六气推算') &&
          (widget.data ?? '').contains('司天：') &&
          (widget.data ?? '').contains('在泉：'),
    );
    expect(returnedToolResult, findsOneWidget);
    expect(service.restoredTranscript, contains('司天：'));
    expect(service.restoredTranscript, contains('在泉：'));
    expect(service.restoredUserMessages, contains('帮我推算五运六气'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一助手对用户指定日期直接执行五运六气并持久化已校验参数', (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '帮我推算五运六气，日期 2026-11-06',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('打开五运六气推算'), findsNothing);
    final resultMessage = store.savedMessages.where((message) =>
        message['role'] == 'assistant' &&
        (message['content'] as String).contains('工具：五运六气推算'));
    expect(resultMessage, hasLength(1));
    expect(resultMessage.single['content'], contains('推算日期：2026-11-06'));

    final metadata = AssistantMessageMetadata.decode(
      resultMessage.single['metadata'] as String,
    );
    expect(metadata.toolId, 'yunqi');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {'date': '2026-11-06'});
    expect(metadata.sourceIds, const ['local-engine:yunqi']);
    expect(service.restoredTranscript, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从普通工具入口打开时不显示助手专用返回操作', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: YunQiScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('将本次推算结果带回助手对话'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('易经起卦结果可以返回统一助手', (tester) async {
    final cast = YiJingEngine.castByNumbers(3, 7);
    String? returnedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returnedResult = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => YiJingResultScreen(
                      cast: cast,
                      returnResultOnComplete: true,
                    ),
                  ),
                );
              },
              child: const Text('打开易经结果'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开易经结果'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回 AI 助手'), findsOneWidget);

    await tester.tap(find.byTooltip('返回 AI 助手'));
    await tester.pumpAndSettle();

    expect(returnedResult, isNotNull);
    expect(returnedResult, contains('易经起卦结果'));
    expect(returnedResult, contains(cast.primary.name));
    expect(returnedResult, contains('民俗文化参考'));
  });


  testWidgets('易经结果页返回时会继续退出工具页并回到统一助手', (tester) async {
    String? returnedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returnedResult = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const YiJingScreen(returnResultOnComplete: true),
                  ),
                );
              },
              child: const Text('打开易经工具'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开易经工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '起卦').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回 AI 助手'), findsOneWidget);
    await tester.tap(find.byTooltip('返回 AI 助手'));
    await tester.pumpAndSettle();

    expect(returnedResult, isNotNull);
    expect(returnedResult, contains('易经起卦结果'));
    expect(tester.takeException(), isNull);
  });



  testWidgets('退出统一助手工具页回传 CANCELLED，不与 NO_RESULT 混淆', (tester) async {
    final service = _RecordingAssistantService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _NoopAssistantConversationStore(),
          imagePicker: _NoLostImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我推算五运六气');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开五运六气推算'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final cancelledResult = find.byWidgetPredicate(
      (widget) => widget is SelectableText &&
          (widget.data ?? '').contains('执行状态：CANCELLED'),
    );
    expect(cancelledResult, findsOneWidget);
    expect(service.restoredTranscript, contains('执行状态：CANCELLED'));
    expect(service.restoredTranscript, isNot(contains('执行状态：NO_RESULT')));
    expect(tester.takeException(), isNull);
  });


  testWidgets('每日黄历在统一助手中本地执行并保存日期、结果和来源', (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我查询今日黄历');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.modelCalls, 0);
    final resultMessages = store.savedMessages.where((message) =>
        message['role'] == 'assistant' &&
        (message['content'] as String).contains('工具：每日黄历'));
    expect(resultMessages, hasLength(1));

    final content = resultMessages.single['content'] as String;
    final metadata = AssistantMessageMetadata.decode(
      resultMessages.single['metadata'] as String,
    );
    final now = DateTime.now();
    final expectedDate =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    expect(content, contains('公历：$expectedDate'));
    expect(content, contains('来源标识：local-engine:almanac'));
    expect(content, contains('传统民俗文化参考'));
    expect(metadata.toolId, 'almanac');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, {'date': expectedDate});
    expect(metadata.sourceIds, const ['local-engine:almanac']);
    expect(tester.takeException(), isNull);
  });


  testWidgets('八字排盘完整结果回到助手时间线并进入本地模型上下文', (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testToolRouteBuilder: (tool, _) {
            if (tool.id == 'bazi') {
              return BaZiPaipanScreen(
                returnResultOnComplete: true,
                initialSolar: DateTime(1995, 8, 16, 12),
                initialIsMale: true,
                initialLng: 120,
                initialLat: 30,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我排八字');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.text('打开八字排盘'), findsOneWidget);

    await tester.tap(find.text('打开八字排盘'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回 AI 助手'), findsOneWidget);

    await tester.tap(find.byTooltip('返回 AI 助手'));
    await tester.pumpAndSettle();

    expect(service.restoredTranscript, contains('【八字排盘完整结果】'));
    expect(service.restoredTranscript, contains('日主强弱：'));
    expect(service.restoredTranscript, contains('格局说明：'));
    expect(service.restoredTranscript, contains('五行分布状态：'));
    expect(service.restoredTranscript, contains('用神：'));
    expect(service.restoredTranscript, contains('忌神：'));
    expect(service.restoredTranscript, contains('【大运】'));
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('日主强弱：')),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('紫微排盘完整十二宫和大限解读回到助手本地模型上下文',
      (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          useMaterial3: true,
          extensions: [AppColors.light],
        ),
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testToolRouteBuilder: (tool, _) {
            if (tool.id == 'ziwei') {
              return ZiweiChartScreen(
                returnResultOnComplete: true,
                initialSolar: DateTime(1990, 6, 15, 10),
                initialGender: true,
                initialLng: 120,
                initialLat: 30,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我排紫微斗数');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.text('打开紫微斗数排盘'), findsOneWidget);

    await tester.tap(find.text('打开紫微斗数排盘'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回 AI 助手'), findsOneWidget);

    await tester.tap(find.byTooltip('返回 AI 助手'));
    await tester.pumpAndSettle();

    expect(service.restoredTranscript, contains('【紫微斗数排盘完整结果】'));
    expect(service.restoredTranscript, contains('【十二宫星曜】'));
    expect(service.restoredTranscript, contains('整体运势：'));
    expect(service.restoredTranscript, contains('大限解读：'));
    expect(service.restoredTranscript, contains('生年四化：'));
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('【十二宫星曜】')),
      isTrue,
    );
    expect(service.restoredTranscript, isNot(contains('身体留意')));
    expect(tester.takeException(), isNull);
  });


  testWidgets('五种民俗/术数工具均把真实计算结果交给助手，并可一键调用 AI 解释',
      (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testToolRouteBuilder: (tool, _) => switch (tool.id) {
            'chenggu' => const ChengguBoneScreen(returnResultOnComplete: true),
            'guansha' => const GuanshaScreen(returnResultOnComplete: true),
            'shousheng_debt' =>
              const ShoushengDebtScreen(returnResultOnComplete: true),
            'huangdi_siji' =>
              const HuangdiSijiScreen(returnResultOnComplete: true),
            'sanshan_lingqian' =>
              const SanshanLingqianScreen(returnResultOnComplete: true),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> execute({
      required String query,
      required String openAction,
      required String runAction,
      required String returnAction,
      required String expectedResult,
    }) async {
      await tester.enterText(find.byType(TextField).first, query);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text(openAction), findsOneWidget, reason: query);
      await tester.tap(find.text(openAction));
      await tester.pumpAndSettle();
      // Some data-backed calculators stay on a loading scaffold after the
      // route animation settles. Wait for the real calculate control before
      // tapping, then wait for the result handoff control.
      await _waitForText(tester, runAction);
      await _scrollUntilTextVisible(tester, runAction);
      await tester.tap(find.text(runAction));
      await tester.pumpAndSettle();
      // Result cards are ListView children and may not be built until scrolled
      // into view; absence from the current viewport is not a missing result.
      await _scrollUntilTextVisible(tester, returnAction);
      await tester.tap(find.text(returnAction));
      await tester.pumpAndSettle();

      expect(service.restoredTranscript, contains(expectedResult));
      expect(
        store.savedMessages.any((message) =>
            message['role'] == 'assistant' &&
            (message['content'] as String).contains(expectedResult)),
        isTrue,
      );
      expect(find.text('AI总结解读'), findsWidgets);
    }

    await execute(
      query: '帮我测算称骨',
      openAction: '打开袁天罡称骨',
      runAction: '称骨测算',
      returnAction: '将本次称骨结果带回助手对话',
      expectedResult: '总骨重：',
    );
    await execute(
      query: '帮我测算小儿关煞',
      openAction: '打开小儿关煞',
      runAction: '测算关煞',
      returnAction: '将本次关煞结果带回助手对话',
      expectedResult: '本地规则结果：',
    );
    await execute(
      query: '帮我查询受生债',
      openAction: '打开受生债查询',
      runAction: '查询受生债',
      returnAction: '将本次受生债查询结果带回助手对话',
      expectedResult: '查询体系：禄库受生经',
    );
    await execute(
      query: '帮我查询黄帝四季歌',
      openAction: '打开轩辕黄帝四季歌',
      runAction: '查询四季歌',
      returnAction: '将本次四季歌结果带回助手对话',
      expectedResult: '对应部位：',
    );
    await execute(
      query: '帮我抽签三山国王灵签',
      openAction: '打开三山国王灵签',
      runAction: '摇签',
      returnAction: '将本次灵签结果带回助手对话',
      expectedResult: '签号：',
    );

    expect(service.modelCalls, 0);
    await tester.tap(find.text('AI总结解读').last);
    await tester.pumpAndSettle();

    expect(service.modelCalls, 1);
    expect(service.restoredTranscript, contains('签号：'));
    expect(service.sentTexts.single, contains('总结并解释'));
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'user' &&
          (message['content'] as String).contains('总结并解释')),
      isTrue,
    );
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('已收到：')),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

}
