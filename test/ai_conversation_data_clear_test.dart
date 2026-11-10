import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/models/bookmark.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-ai-clear-',
    );
    DatabaseHelper.configureTestDatabase(
      'ai_clear_test.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  Future<void> seedAiAndNonAiData() async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation(
      title: '待清除会话',
      mode: 'consultation',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '用户自述内容',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '助手回复内容',
    );
    final db = await store.database;
    await db.insert('tcm_interview_tasks', {
      'conversation_id': conversationId,
      'task_id': 'task-clear-1',
      'status': 'in_progress',
      'state_json': '{"pendingPromptId":"temperature"}',
      'updated_at': '2026-11-10T00:00:00Z',
    });
    await store.saveChatMessage('旧版聊天记录', true);

    await store.insertBookmark(
      Bookmark(
        title: '保留收藏',
        content: '收藏内容',
        category: '知识',
        source: 'manual',
      ),
    );
    await db.insert('user_settings', {'key': 'theme', 'value': 'dark'});
    await db.insert('diagnosis_history', {
      'meridian': '少阳',
      'pattern': '少阳证',
      'formula': '小柴胡汤',
      'confidence': 0.8,
      'answers': '{}',
      'created_at': '2026-11-10T00:00:00Z',
    });
    await db.insert('user_charts', {
      'name': '保留命盘',
      'gender': 1,
      'solar_iso': '1980-01-01T00:00:00',
      'created_at': 1794268800,
    });
  }

  test('clears all four AI conversation tables and preserves unrelated app data',
      () async {
    await seedAiAndNonAiData();
    final store = DatabaseHelper.instance;
    final db = await store.database;

    final counts = await store.clearAiConversationData();

    expect(counts['assistantMessages'], 2);
    expect(counts['tcmInterviewTasks'], 1);
    expect(counts['assistantConversations'], 1);
    expect(counts['legacyChatMessages'], 1);

    expect(await db.query('assistant_messages'), isEmpty);
    expect(await db.query('tcm_interview_tasks'), isEmpty);
    expect(await db.query('assistant_conversations'), isEmpty);
    expect(await db.query('chat_history'), isEmpty);

    expect(await db.query('bookmarks'), hasLength(1));
    expect(await db.query('user_settings'), hasLength(1));
    expect(await db.query('diagnosis_history'), hasLength(1));
    expect(await db.query('user_charts'), hasLength(1));
  });

  test('transaction rolls back child deletions if parent deletion fails',
      () async {
    await seedAiAndNonAiData();
    final store = DatabaseHelper.instance;
    final db = await store.database;
    await db.execute('''
      CREATE TRIGGER block_assistant_conversation_delete
      BEFORE DELETE ON assistant_conversations
      BEGIN
        SELECT RAISE(ABORT, 'intentional clear transaction failure');
      END
    ''');

    await expectLater(
      store.clearAiConversationData(),
      throwsA(isA<Exception>()),
    );

    // Messages/tasks are deleted before conversations. Their rows must be
    // restored by SQLite when the parent delete aborts the transaction.
    expect(await db.query('assistant_messages'), hasLength(2));
    expect(await db.query('tcm_interview_tasks'), hasLength(1));
    expect(await db.query('assistant_conversations'), hasLength(1));
    expect(await db.query('chat_history'), hasLength(1));
  });
}
