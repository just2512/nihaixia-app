import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

const _readyStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: true,
  modelPath: '/test/gemma-4-E4B-it.litertlm',
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

class _PersistentHistoryService extends LocalAiService {
  String? restoredTranscript;

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

  @override
  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
  }) async {
    restoredTranscript = transcript;
  }

  @override
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
  }) async =>
      '续聊成功：$text';
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('reopened SQLite restores FAILED tool and persists its retry result',
      (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await DatabaseHelper.closeTestDatabase();
    });
    final databaseName =
        'assistant_history_recovery_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.configureTestDatabase(databaseName);
    final store = DatabaseHelper.instance;

    final conversationId = await store.createAssistantConversation(
      title: '持久化失败重试',
      mode: 'metaphysics',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '帮我推算五运六气',
      metadata: AssistantMessageMetadata(
        mode: 'metaphysics',
        selectedMode: 'automatic',
        replayable: true,
      ).encode(),
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '【五运六气推算执行结果】\\n执行状态：FAILED\\n执行参数：date=2026-11-07',
      metadata: AssistantMessageMetadata(
        mode: 'metaphysics',
        selectedMode: 'automatic',
        toolId: 'yunqi',
        toolStatus: 'FAILED',
        toolArguments: const {'date': '2026-11-07'},
      ).encode(),
    );

    // Close the SQLite handle and reopen the same on-disk database. This
    // verifies disk persistence across a database-connection restart; it does
    // not claim to simulate Android process death.
    await DatabaseHelper.closeTestDatabase();
    DatabaseHelper.configureTestDatabase(databaseName);

    final persistedMessages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(persistedMessages, hasLength(2));
    final persistedMetadata = AssistantMessageMetadata.decode(
      persistedMessages.last['metadata']! as String,
    );
    expect(persistedMetadata.toolStatus, 'FAILED');
    expect(persistedMetadata.toolArguments, const {'date': '2026-11-07'});

    final service = _PersistentHistoryService();
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
    await tester.tap(find.text('持久化失败重试'));
    await _pumpFrames(tester);

    expect(find.text('重试五运六气推算'), findsOneWidget);
    expect(find.textContaining('执行状态：FAILED'), findsOneWidget);
    expect(service.restoredTranscript, contains('执行参数：date=2026-11-07'));

    await tester.tap(find.text('重试五运六气推算'));
    await _pumpFrames(tester);
    final returnResult = find.text('将本次推算结果带回助手对话');
    await tester.ensureVisible(returnResult);
    await tester.pumpAndSettle();
    await tester.tap(returnResult);
    await _pumpFrames(tester);

    final retriedMessages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(retriedMessages.last['content'], contains('执行状态：SUCCEEDED'));
    expect(retriedMessages.last['content'], contains('执行参数：date=2026-11-07'));
    final retriedMetadata = AssistantMessageMetadata.decode(
      retriedMessages.last['metadata']! as String,
    );
    expect(retriedMetadata.toolStatus, 'SUCCEEDED');
    expect(retriedMetadata.toolArguments, const {'date': '2026-11-07'});
    expect(service.restoredTranscript, contains('执行状态：SUCCEEDED'));
    expect(tester.takeException(), isNull);
  });
}
