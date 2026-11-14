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
import 'package:nihaisha_app/screens/sanshan_lingqian_screen.dart';
import 'package:nihaisha_app/data/sanshan_lingqian_data.dart';
import 'package:nihaisha_app/data/saved_chart_repository.dart';
import 'package:nihaisha_app/services/sanshan_lingqian_tool_executor.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';
import 'package:nihaisha_app/services/bazi_tool_executor.dart';
import 'package:nihaisha_app/services/ziwei_tool_executor.dart';


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
    expect(service.modelCalls, 1);
    expect(service.restoredTranscript, contains('岁运：'));
    expect(
      store.savedMessages.where((message) =>
          message['role'] == 'user' &&
          (message['content'] as String).contains('总结并解释')),
      isEmpty,
    );
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('已收到：')),
      isTrue,
    );
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

    expect(service.modelCalls, 1);
    expect(find.text('AI总结解读'), findsNothing);
    final resultMessages = store.savedMessages.where((message) =>
        message['role'] == 'assistant' &&
        (message['content'] as String).contains('工具：每日黄历'));
    expect(resultMessages, hasLength(1));
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('已收到：')),
      isTrue,
      reason: '已校验的黄历结果应由助手自动归纳',
    );

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


  testWidgets('八字助手在当前对话后台调用本地引擎并把完整结果交给 AI 解读',
      (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    const expectedArguments = <String, String>{
      'birth_date': '1995-08-16',
      'birth_time': '12:00',
      'gender': 'male',
      'birthplace': '上海市',
    };
    // Run the resource-backed deterministic engine before mounting the widget.
    // This keeps the engine's rootBundle IO out of the widget's fake-async zone.
    String? enginePreparationError;
    final preparedResult = await tester.runAsync(() async {
      try {
        return await BaziToolExecutor.execute(expectedArguments);
      } catch (error, stackTrace) {
        enginePreparationError = '$error\\n$stackTrace';
        rethrow;
      }
    });
    expect(
      preparedResult?.status,
      AssistantToolExecutionStatus.succeeded,
      reason: '本地八字引擎准备真实结果失败：$enginePreparationError',
    );
    var pageOpened = false;
    Map<String, String>? executedArguments;
    AssistantToolResult? executedResult;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testToolRouteBuilder: (tool, _) {
            pageOpened = true;
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments = Map<String, String>.from(arguments);
            executedResult = preparedResult;
            return preparedResult!;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄学大师').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '帮我排八字；出生日期：1995-08-16；出生时间：12:00；性别：男；出生地：上海市',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(pageOpened, isFalse);
    expect(find.text('打开八字排盘'), findsNothing);
    expect(
      executedArguments,
      expectedArguments,
      reason: '后台执行必须收到从用户原话提取并校验的完整出生参数',
    );
    expect(
      executedResult?.status,
      AssistantToolExecutionStatus.succeeded,
      reason: '助手必须把独立执行并验证过的真实本地排盘结果交给会话；失败原因：${executedResult?.values['未执行原因']}',
    );
    expect(executedResult?.validateFor('bazi'), isEmpty);
    expect(
      executedResult?.validateArgumentsMatch(executedArguments!),
      isEmpty,
    );
    expect(find.text('AI总结解读'), findsNothing);
    expect(service.modelCalls, 1);
    expect(service.restoredTranscript, contains('【八字排盘完整结果】'));
    expect(service.restoredTranscript, contains('出生时间：1995-08-16 12:00'));
    expect(service.restoredTranscript, contains('日主强弱：'));
    expect(service.restoredTranscript, contains('格局说明：'));
    expect(service.restoredTranscript, contains('五行分布状态：'));
    expect(service.restoredTranscript, contains('用神：'));
    expect(service.restoredTranscript, contains('忌神：'));
    expect(service.restoredTranscript, contains('【大运】'));
    expect(
      service.sentTexts.any((text) => text.contains('总结并解释刚才由 App 本地引擎返回的八字排盘结果')),
      isTrue,
    );
    expect(
      store.savedMessages.any((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('日主强弱：')),
      isTrue,
    );
    expect(
      store.savedMessages.where((message) =>
          message['role'] == 'user' &&
          (message['content'] as String).contains(
              '总结并解释刚才由 App 本地引擎返回的八字排盘结果')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('紫微助手在对话中调用本地引擎并把完整十二宫结果交给 AI 解读',
      (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    const expectedArguments = <String, String>{
      'birth_date': '1990-06-15',
      'birth_time': '10:00',
      'gender': 'male',
      'birthplace': '上海市',
    };
    String? enginePreparationError;
    final preparedResult = await tester.runAsync(() async {
      try {
        return await ZiweiToolExecutor.execute(expectedArguments);
      } catch (error, stackTrace) {
        enginePreparationError = '$error\\n$stackTrace';
        rethrow;
      }
    });
    expect(
      preparedResult?.status,
      AssistantToolExecutionStatus.succeeded,
      reason: '本地紫微引擎准备真实结果失败：$enginePreparationError',
    );
    var pageOpened = false;
    Map<String, String>? executedArguments;
    AssistantToolResult? executedResult;
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
            if (tool.id == 'ziwei') pageOpened = true;
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments = Map<String, String>.from(arguments);
            executedResult = preparedResult;
            return preparedResult!;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄学大师').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '帮我排紫微斗数；出生日期：1990-06-15；出生时间：10:00；性别：男；出生地：上海市',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(pageOpened, isFalse);
    expect(find.text('打开紫微斗数排盘'), findsNothing);
    expect(executedArguments, expectedArguments);
    expect(
      executedResult?.status,
      AssistantToolExecutionStatus.succeeded,
      reason: '必须只把本地紫微引擎的有效结果交给助手；失败原因：${executedResult?.values['未执行原因']}',
    );
    expect(executedResult?.validateFor('ziwei'), isEmpty);
    expect(
      executedResult?.validateArgumentsMatch(executedArguments!),
      isEmpty,
    );
    expect(service.modelCalls, 1);
    expect(service.restoredTranscript, contains('【紫微斗数排盘完整结果】'));
    expect(service.restoredTranscript, contains('【十二宫星曜】'));
    expect(service.restoredTranscript, contains('整体运势：'));
    expect(service.restoredTranscript, contains('大限解读：'));
    expect(service.restoredTranscript, contains('生年四化：'));
    expect(service.restoredTranscript, contains('出生时间：1990-06-15 10:00'));
    expect(
      service.sentTexts.single,
      contains('自动总结并解释实际输入、关键输出、字段含义'),
    );
    final resultMessage = store.savedMessages.firstWhere(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('【紫微斗数排盘完整结果】'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'ziwei');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, expectedArguments);
    expect(metadata.sourceIds, const [
      'local-engine:ziwei',
      'local-data:city-locations',
    ]);
    expect(
      metadata.sourceIds,
      isNot(contains('local-page-tool:ziwei')),
    );
    expect(
      store.savedMessages.where((message) =>
          message['role'] == 'user' &&
          (message['content'] as String).contains('总结并解释刚才由 App 本地引擎返回')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('三山国王抽签在当前助手对话调用本地签谱；打开签谱仍进入浏览页面', (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    final expectedSign = kSanShanLingqian.first;
    final expectedResult = SanshanLingqianToolExecutor.resultForSign(expectedSign);
    var pageOpened = false;
    Map<String, String>? executedArguments;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testToolRouteBuilder: (tool, _) {
            if (tool.id == 'sanshan_lingqian') {
              pageOpened = true;
              return const SanshanLingqianScreen(returnResultOnComplete: true);
            }
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments = Map<String, String>.unmodifiable(arguments);
            return expectedResult;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '帮我抽签三山国王灵签');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(pageOpened, isFalse, reason: '抽签应在当前对话调用 App 本地签谱，不跳转页面');
    expect(executedArguments, isEmpty);
    expect(service.modelCalls, 1);
    expect(service.restoredTranscript, contains(expectedSign.verse));
    expect(service.restoredTranscript, contains('签号：1'));
    expect(service.restoredTranscript, contains('来源标识：local-data:sanshan-lingqian:1'));
    expect(service.sentTexts.single, contains('不是科学预测'));
    expect(service.sentTexts.single, contains('不鼓励用户据此作重大决定'));

    final resultMessage = store.savedMessages.firstWhere(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('工具：三山国王灵签'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'sanshan_lingqian');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.sourceIds, const ['local-data:sanshan-lingqian:1']);
    expect(metadata.toolArguments, isEmpty);

    await tester.enterText(find.byType(TextField).first, '打开三山国王灵签');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    // The same string remains in the input field after sending; select the
    // assistant's action link rather than matching both the input and link.
    expect(find.text('打开三山国王灵签'), findsNWidgets(2));
    await tester.tap(find.text('打开三山国王灵签').last);
    await tester.pumpAndSettle();
    expect(pageOpened, isTrue, reason: '仅查阅签谱时仍保留原页面浏览路径');
    expect(find.text('签谱'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('已保存命盘在聊天中先选记录再选排盘类型，并由 App 执行后交给 AI 解读', (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    final charts = [
      SavedChart(
        id: 41,
        name: '家庭命盘 A',
        isMale: true,
        solarIso: DateTime(1990, 1, 2, 8, 30).toIso8601String(),
        lng: 121.47,
        lat: 31.23,
        cityName: '上海市',
        createdAt: 200,
      ),
      SavedChart(
        id: 42,
        name: '个人命盘 B',
        isMale: false,
        solarIso: DateTime(1988, 6, 7, 12, 0).toIso8601String(),
        createdAt: 100,
      ),
    ];
    Map<String, String>? executedArguments;
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testSavedChartsLoader: () async => charts,
          testToolRouteBuilder: (tool, _) {
            if (tool.id == 'saved_charts') {
              pageOpened = true;
              return const SizedBox.shrink();
            }
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments = Map<String, String>.unmodifiable(arguments);
            return AssistantToolResult(
              toolId: 'saved_charts',
              title: '我的命盘库',
              values: const {
                '保存记录 ID': '42',
                '保存记录名称': '个人命盘 B',
                '排盘类型': '八字',
                '出生时间': '1988-06-07T12:00:00.000',
                '出生地点': '保存记录未存地点坐标；App 原引擎按默认东经120°、北纬30°计算',
                '完整排盘结果': '【八字排盘完整结果】\n四柱：戊辰、戊午、甲寅、庚午',
              },
              sourceIds: const [
                'local-data:saved-chart:42',
                'local-engine:bazi',
              ],
              arguments: Map<String, String>.unmodifiable(arguments),
              disclaimer: '本次使用 App 原有确定性八字引擎重新计算；传统命理不是科学预测。',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '查看我的命盘库');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(pageOpened, isFalse, reason: '命盘库请求应留在当前助手对话');
    expect(executedArguments, isNull, reason: '尚未选择记录和类型，不得执行重算');
    expect(service.modelCalls, 0, reason: '参数澄清不需要调用模型');
    expect(find.textContaining('ID 41｜家庭命盘 A'), findsOneWidget);
    expect(find.textContaining('ID 42｜个人命盘 B'), findsOneWidget);
    expect(find.textContaining('出生时间：1988'), findsNothing,
        reason: '列表选择阶段不把出生细节暴露到对话');

    final waitingForRecord = store.savedMessages.lastWhere(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('请回复记录 ID'),
    );
    var waitingMetadata = AssistantMessageMetadata.decode(
      waitingForRecord['metadata'] as String,
    );
    expect(waitingMetadata.toolId, 'saved_charts');
    expect(waitingMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(waitingMetadata.toolArguments, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'ID 42');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(executedArguments, isNull, reason: '仍未选择八字或紫微');
    expect(service.modelCalls, 0);
    expect(store.savedMessages.last['content'] as String, contains('请明确选择排盘类型'));
    waitingMetadata = AssistantMessageMetadata.decode(
      store.savedMessages.last['metadata'] as String,
    );
    expect(waitingMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(waitingMetadata.toolArguments, const {'saved_chart_id': '42'});

    await tester.enterText(find.byType(TextField).first, '八字');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(pageOpened, isFalse);
    expect(executedArguments, const {
      'saved_chart_id': '42',
      'chart_type': 'bazi',
    });
    expect(service.modelCalls, 1, reason: '只有 App 返回真实排盘结果后才调用 E4B 解读');
    expect(service.restoredTranscript, contains('四柱：戊辰、戊午、甲寅、庚午'));
    expect(service.restoredTranscript, contains('local-data:saved-chart:42'));
    expect(service.sentTexts.single, contains('不是科学预测'));
    expect(service.sentTexts.single, contains('不得描述为用户实际出生地'));

    final resultMessage = store.savedMessages.firstWhere(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('工具：我的命盘库'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'saved_charts');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'saved_chart_id': '42',
      'chart_type': 'bazi',
    });
    expect(metadata.sourceIds, const [
      'local-data:saved-chart:42',
      'local-engine:bazi',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已保存命盘未执行时可以在聊天中取消', (tester) async {
    final service = _RecordingAssistantService();
    final store = _NoopAssistantConversationStore();
    final charts = [
      SavedChart(
        id: 7,
        name: '待选命盘',
        isMale: true,
        solarIso: DateTime(1990, 1, 2, 8, 30).toIso8601String(),
        createdAt: 1,
      ),
    ];
    var executorCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          testSavedChartsLoader: () async => charts,
          testHeadlessToolExecutor: (arguments) {
            executorCalled = true;
            throw StateError('取消后不应执行');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '查看我的命盘库');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(executorCalled, isFalse);

    await tester.enterText(find.byType(TextField).first, '取消命盘查询');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(executorCalled, isFalse);
    expect(service.modelCalls, 0);
    expect(store.savedMessages.last['content'] as String, contains('已取消本次命盘查询'));
    final metadata = AssistantMessageMetadata.decode(
      store.savedMessages.last['metadata'] as String,
    );
    expect(metadata.toolId, 'saved_charts');
    expect(metadata.toolStatus, 'CANCELLED');
    expect(tester.takeException(), isNull);
  });

}
