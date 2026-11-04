import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' show Timeout;
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('assistant_messages');
    await db.delete('assistant_conversations');
  });

  testWidgets(
    '打开历史会话后继续发送，消息仍写入原会话',
    (tester) async {
      print('history-resume: begin');
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation(
      title: '可继续的历史会话',
      mode: 'consultation',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '我最近口苦，睡眠也不好',
      metadata: 'selectedMode=consultation;mode=consultation',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '口苦持续多久？夜间是否容易醒？',
      metadata: 'selectedMode=consultation;mode=consultation',
    );

    final service = _HistoryResumeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          imagePicker: _NoLostImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    print('history-resume: initial screen settled');

    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    print('history-resume: history list settled');
    expect(find.text('可继续的历史会话'), findsOneWidget);

    await tester.tap(find.text('可继续的历史会话'));
    await tester.pumpAndSettle();
    print('history-resume: selected history restored');

    expect(service.restoredTranscript, contains('我最近口苦，睡眠也不好'));
    expect(service.restoredTranscript, contains('口苦持续多久？'));
    expect(
      service.restoredUserMessages,
      contains('我最近口苦，睡眠也不好'),
    );

    await tester.enterText(find.byType(TextField), '继续补充：舌苔薄白');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    print('history-resume: send tapped');
    await tester.pumpAndSettle();
    print('history-resume: send settled');

    final messages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    print('history-resume: messages fetched');
    expect(messages, hasLength(4));
    expect(messages[2]['role'], 'user');
    expect(messages[2]['content'], '继续补充：舌苔薄白');
    expect(messages[3]['role'], 'assistant');
    expect(messages[3]['content'], '续聊成功：继续补充：舌苔薄白');

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    expect(conversations.single['id'], conversationId);
    expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
