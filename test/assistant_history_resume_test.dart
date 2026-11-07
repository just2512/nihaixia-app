import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';
import 'package:nihaisha_app/services/tcm_interview_conversation_controller.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';

const _readyStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: true,
  modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'cpu',
);

class _NoLostImagePicker implements LocalAiImagePicker {
  @override
  Future<String?> pickCameraImagePath() async => null;

  @override
  Future<String?> retrieveLostImagePath() async => null;
}

class _HistoryResumeService extends LocalAiService {
  String? restoredTranscript;
  List<String> restoredUserMessages = const [];

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

  @override
  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
  }) async {
    restoredTranscript = transcript;
    restoredUserMessages = List<String>.from(userMessages);
  }

  @override
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
  }) async =>
      '续聊成功：$text';
}

class _MemoryConversationStore implements AssistantConversationStore {
  int _nextId = 3;
  int _nextMessageId = 5;

  final Map<int, Map<String, Object?>> conversations = {
    1: {
      'id': 1,
      'title': '可继续的历史会话',
      'mode': 'consultation',
      'created_at': '2026-11-04T08:00:00.000',
      'updated_at': '2026-11-04T08:10:00.000',
      'last_message_preview': '口苦持续多久？夜间是否容易醒？',
    },
    2: {
      'id': 2,
      'title': '待执行工具会话',
      'mode': 'metaphysics',
      'created_at': '2026-11-04T08:05:00.000',
      'updated_at': '2026-11-04T08:15:00.000',
      'last_message_preview': '已识别到你要使用五运六气推算。',
    },
  };

  final Map<int, TcmInterviewTaskState> taskStates = {};

  final Map<int, List<Map<String, Object?>>> messages = {
    1: [
      {
        'id': 1,
        'conversation_id': 1,
        'role': 'user',
        'content': '我最近口苦，睡眠也不好',
        'metadata': 'selectedMode=consultation;mode=consultation',
      },
      {
        'id': 2,
        'conversation_id': 1,
        'role': 'assistant',
        'content': '口苦持续多久？夜间是否容易醒？',
        'metadata': 'selectedMode=consultation;mode=consultation',
      },
    ],
    2: [
      {
        'id': 3,
        'conversation_id': 2,
        'role': 'user',
        'content': '帮我推算五运六气',
        'metadata': 'selectedMode=automatic;mode=metaphysics;replayable=true',
      },
      {
        'id': 4,
        'conversation_id': 2,
        'role': 'assistant',
        'content': '已识别到你要使用「五运六气推算」。实际计算由 App 内置工具执行。',
        'metadata': 'mode=metaphysics;selectedMode=automatic;tool=yunqi',
      },
    ],
  };

  @override
  Future<int> createAssistantConversation({
    String title = '新对话',
    String mode = 'general',
  }) async {
    final id = _nextId++;
    conversations[id] = {
      'id': id,
      'title': title,
      'mode': mode,
      'created_at': '2026-11-04T08:20:00.000',
      'updated_at': '2026-11-04T08:20:00.000',
      'last_message_preview': '',
    };
    messages[id] = [];
    return id;
  }

  @override
  Future<int> saveAssistantMessage({
    required int conversationId,
    required String role,
    required String content,
    String? metadata,
  }) async {
    final row = <String, Object?>{
      'id': _nextMessageId++,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'metadata': metadata,
    };
    messages.putIfAbsent(conversationId, () => []).add(row);
    final conversation = conversations[conversationId]!;
    conversation['updated_at'] = '2026-11-04T08:30:00.000';
    conversation['last_message_preview'] = content;
    return row['id']! as int;
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  }) async {
    final rows = conversations.values
        .where((row) => (messages[row['id']] ?? const []).isNotEmpty)
        .toList()
      ..sort((a, b) => (b['updated_at'] as String)
          .compareTo(a['updated_at'] as String));
    return limit == null ? rows : rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  }) async =>
      List<Map<String, Object?>>.from(messages[conversationId] ?? const []);

  @override
  Future<void> saveTcmInterviewTaskState({
    required int conversationId,
    required TcmInterviewTaskState state,
  }) async {
    taskStates[conversationId] = state;
  }

  @override
  Future<TcmInterviewTaskState?> getTcmInterviewTaskState({
    required int conversationId,
  }) async =>
      taskStates[conversationId];

  @override
  Future<void> deleteAssistantConversations(List<int> conversationIds) async {
    for (final id in conversationIds) {
      conversations.remove(id);
      messages.remove(id);
      taskStates.remove(id);
    }
  }
}

void main() {
  testWidgets('恢复历史会话时保留尚未执行的工具操作入口', (tester) async {
    final store = _MemoryConversationStore();
    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    final orderedConversations = await store.getAssistantConversations();
    expect(orderedConversations, hasLength(2));
    expect(orderedConversations.first['id'], 2);

    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await _pumpFrames(tester, frames: 24);
    expect(find.text('历史对话'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
    // The newest session (id 2) is the first row by updated_at ordering.
    await tester.tap(find.byType(ListTile).first);
    await _pumpFrames(tester);

    expect(find.text('打开五运六气推算'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('恢复 FAILED 工具结果时显示重试入口并保留原始参数', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryConversationStore();
    // Remove the fixture's earlier pending tool action so this test isolates
    // the FAILED result rather than asserting against another message.
    store.messages[2]![1]['metadata'] = AssistantMessageMetadata(
      mode: 'metaphysics',
      selectedMode: 'automatic',
    ).encode();
    store.messages[2]!.add({
      'id': 5,
      'conversation_id': 2,
      'role': 'assistant',
      'content': '【五运六气推算执行结果】\\n执行状态：FAILED\\n执行参数：date=2026-11-07',
      'metadata': AssistantMessageMetadata(
        mode: 'metaphysics',
        selectedMode: 'automatic',
        toolId: 'yunqi',
        toolStatus: 'FAILED',
        toolArguments: const {'date': '2026-11-07'},
      ).encode(),
    });
    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    await tester.tap(find.byType(ListTile).first);
    await _pumpFrames(tester);

    expect(find.text('重试五运六气推算'), findsOneWidget);
    await tester.tap(find.text('重试五运六气推算'));
    await _pumpFrames(tester);

    expect(find.text('五运六气推算'), findsWidgets);
    expect(find.text('2026-11-07'), findsWidgets);
    final returnResult = find.text('将本次推算结果带回助手对话');
    await tester.ensureVisible(returnResult);
    await tester.pumpAndSettle();
    await tester.tap(returnResult);
    await _pumpFrames(tester);

    final messages = await store.getAssistantMessages(conversationId: 2);
    final resultMessage = messages.last;
    expect(resultMessage['content'], contains('执行状态：SUCCEEDED'));
    expect(resultMessage['content'], contains('执行参数：date=2026-11-07'));
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata']! as String,
    );
    expect(metadata.toolId, 'yunqi');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {'date': '2026-11-07'});
    expect(metadata.sourceIds, const ['local-engine:yunqi']);
    expect(service.restoredTranscript, contains('执行状态：SUCCEEDED'));
    expect(tester.takeException(), isNull);
  });


  testWidgets('恢复知识检索状态和来源引用后仍可在历史消息中查看', (tester) async {
    final store = _MemoryConversationStore();
    store.messages[1]!.add({
      'id': 5,
      'conversation_id': 1,
      'role': 'assistant',
      'content': '检索到方剂条目。',
      'metadata': AssistantMessageMetadata(
        mode: 'learning',
        selectedMode: 'automatic',
        sourceIds: const ['formula:gui-zhi-tang'],
        knowledgeStatus: 'PARTIAL',
      ).encode(),
    });
    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    await tester.tap(find.text('可继续的历史会话'));
    await _pumpFrames(tester);

    expect(find.text('知识检索：部分结果'), findsOneWidget);
    expect(find.text('方剂：gui-zhi-tang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出工具页会以 CANCELLED 状态写回统一会话', (tester) async {
    final store = _MemoryConversationStore();
    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    await tester.tap(find.byType(ListTile).first);
    await _pumpFrames(tester);

    await tester.tap(find.text('打开五运六气推算'));
    await _pumpFrames(tester);
    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);

    final messages = await store.getAssistantMessages(conversationId: 2);
    final resultMessage = messages.last;
    expect(resultMessage['role'], 'assistant');
    expect(resultMessage['content'], contains('执行状态：CANCELLED'));
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata']! as String,
    );
    expect(metadata.toolId, 'yunqi');
    expect(metadata.toolStatus, 'CANCELLED');
    expect(metadata.replayable, isTrue);
    // The returned result must also be injected into the next model turn's context.
    expect(service.restoredTranscript, contains('执行状态：CANCELLED'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开历史会话后继续发送，消息仍写入原会话', (tester) async {
    final store = _MemoryConversationStore();
    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    expect(find.text('可继续的历史会话'), findsOneWidget);

    await tester.tap(find.text('可继续的历史会话'));
    await _pumpFrames(tester);

    expect(service.restoredTranscript, contains('我最近口苦，睡眠也不好'));
    expect(service.restoredTranscript, contains('口苦持续多久？'));
    expect(
      service.restoredUserMessages,
      contains('我最近口苦，睡眠也不好'),
    );

    await tester.enterText(find.byType(TextField), '继续补充：舌苔薄白');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await _pumpFrames(tester);

    final messages = await store.getAssistantMessages(conversationId: 1);
    expect(messages, hasLength(4));
    expect(messages[2]['role'], 'user');
    expect(messages[2]['content'], '继续补充：舌苔薄白');
    expect(messages[3]['role'], 'assistant');
    expect(messages[3]['content'], '续聊成功：继续补充：舌苔薄白');

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(2));
    expect(conversations.first['id'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复历史结构化问诊后可以继续当前问题并写回原会话', (tester) async {
    final store = _MemoryConversationStore();
    final controller = TcmInterviewConversationController(
      defaultGender: '男',
    );
    controller.start(initialUserMessage: '开始规则问诊');
    final taskState = controller.createTaskState();
    final pendingPrompt = taskState.pendingPromptText!;

    store.taskStates[1] = taskState;
    store.messages[1] = [
      {
        'id': 1,
        'conversation_id': 1,
        'role': 'user',
        'content': '开始规则问诊',
        'metadata': 'selectedMode=automatic;mode=consultation',
      },
      {
        'id': 2,
        'conversation_id': 1,
        'role': 'assistant',
        'content': pendingPrompt,
        'metadata': 'mode=consultation',
      },
    ];

    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    await tester.tap(find.text('可继续的历史会话'));
    await _pumpFrames(tester);

    expect(find.text(pendingPrompt), findsOneWidget);
    expect(find.widgetWithText(ActionChip, taskState.pendingOptions.first),
        findsOneWidget);

    final selectedOption = taskState.pendingOptions.first;
    await tester.tap(find.widgetWithText(ActionChip, selectedOption));
    await _pumpFrames(tester);

    final resumedState = store.taskStates[1]!;
    expect(resumedState.pendingPromptId, 'tongue_pulse');
    final messages = await store.getAssistantMessages(conversationId: 1);
    expect(messages, hasLength(4));
    expect(messages[2]['role'], 'user');
    expect(messages[2]['content'], selectedOption);
    expect(messages[3]['role'], 'assistant');
    expect(messages[3]['content'], resumedState.pendingPromptText);
    expect(service.restoredTranscript, contains('开始规则问诊'));
    expect(tester.takeException(), isNull);
  });


  testWidgets('恢复 CANCELLED 工具结果时保留终态且不显示重试入口', (tester) async {
    final store = _MemoryConversationStore();
    // The base fixture also contains a separate unfinished tool request.
    // Remove that action so this test checks only the CANCELLED terminal row.
    store.messages[2]![1]['metadata'] = AssistantMessageMetadata(
      mode: 'metaphysics',
      selectedMode: 'automatic',
    ).encode();
    store.messages[2]!.add({
      'id': 5,
      'conversation_id': 2,
      'role': 'assistant',
      'content': '【五运六气推算执行结果】\\n执行状态：CANCELLED',
      'metadata': AssistantMessageMetadata(
        mode: 'metaphysics',
        selectedMode: 'automatic',
        toolId: 'yunqi',
        toolStatus: 'CANCELLED',
        toolArguments: const {'date': '2026-11-07'},
        replayable: true,
      ).encode(),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: _HistoryResumeService(),
          imagePicker: _NoLostImagePicker(),
          conversationStore: store,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    await tester.tap(find.byType(ListTile).first);
    await _pumpFrames(tester);

    expect(find.text('重试五运六气推算'), findsNothing);
    expect(find.text('打开五运六气推算'), findsNothing);
    expect(find.textContaining('执行状态：CANCELLED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
