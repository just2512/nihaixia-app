import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

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
  int _nextId = 2;
  int _nextMessageId = 3;

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
  Future<void> deleteAssistantConversations(List<int> conversationIds) async {
    for (final id in conversationIds) {
      conversations.remove(id);
      messages.remove(id);
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

    await tester.tap(find.byTooltip('历史对话'));
    await _pumpFrames(tester);
    await tester.scrollUntilVisible(
      find.text('待执行工具会话'),
      240,
      scrollable: find.descendant(
        of: find.byType(AssistantHistoryScreen),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.tap(find.text('待执行工具会话'));
    await _pumpFrames(tester);

    expect(find.text('打开五运六气推算'), findsOneWidget);
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
    expect(conversations, hasLength(1));
    expect(conversations.single['id'], 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
