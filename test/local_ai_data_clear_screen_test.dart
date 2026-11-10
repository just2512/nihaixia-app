import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_attachment_storage.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

const _installedButReleased = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  hashVerified: true,
  ready: false,
  modelPath: '/app/files/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'not_loaded',
);

class _ClearAiService extends LocalAiService {
  var clearCalls = 0;

  @override
  Future<LocalAiModelStatus> getStatus() async => _installedButReleased;

  @override
  Future<LocalAiModelStatus> clearAiData() async {
    clearCalls++;
    return _installedButReleased;
  }
}

class _NoLostImagePicker implements LocalAiImagePicker {
  @override
  Future<String?> pickCameraImagePath() async => null;

  @override
  Future<String?> retrieveLostImagePath() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory databaseDirectory;
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-ai-clear-screen-db-',
    );
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-ai-clear-screen-cache-',
    );
    DatabaseHelper.configureTestDatabase(
      'ai_clear_screen.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );
    messenger.setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return temporaryDirectory.path;
      }
      throw MissingPluginException('Unexpected path provider call: ${call.method}');
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProvider, null);
    await DatabaseHelper.closeTestDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('clear-all action deletes AI data and preserves model and unrelated data',
      (tester) async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation(
      title: '旧 AI 会话',
      mode: 'consultation',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '旧用户消息',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '旧助手消息',
    );
    final db = await store.database;
    await db.insert('tcm_interview_tasks', {
      'conversation_id': conversationId,
      'task_id': 'clear-screen-task',
      'status': 'in_progress',
      'state_json': '{}',
      'updated_at': '2026-11-10T00:00:00Z',
    });
    await store.saveChatMessage('旧版聊天消息', true);
    await store.insertBookmark(
      const Bookmark(
        title: '保留收藏',
        content: '收藏内容',
        category: '知识',
        source: 'manual',
      ),
    );

    final service = _ClearAiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          attachmentStorage: LocalAiAttachmentStorage(
            temporaryDirectoryProvider: () async => temporaryDirectory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('清除全部 AI 数据'));
    await tester.pumpAndSettle();
    expect(find.text('清除全部 AI 数据？'), findsOneWidget);
    expect(find.textContaining('已导入的 Gemma 模型文件会保留'), findsOneWidget);

    await tester.tap(find.text('清除数据'));
    await tester.pumpAndSettle();

    expect(service.clearCalls, 1);
    expect(await db.query('assistant_messages'), isEmpty);
    expect(await db.query('tcm_interview_tasks'), isEmpty);
    expect(await db.query('assistant_conversations'), isEmpty);
    expect(await db.query('chat_history'), isEmpty);
    expect(await db.query('bookmarks'), hasLength(1));
    expect(find.text('你可以直接描述身体情况、学习问题，或选择 App 内置工具。'), findsOneWidget);
    expect(find.textContaining('AI 数据已清除'), findsOneWidget);
  });
}
