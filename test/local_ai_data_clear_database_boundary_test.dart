import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory databaseDirectory;
  final store = DatabaseHelper.instance;

  setUp(() async {
    sqfliteFfiInit();
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-ai-clear-boundary-',
    );
    DatabaseHelper.configureTestDatabase(
      'ai_clear_boundary_test.db',
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

  test(
    'clears AI conversation tables and preserves non-AI user data after reopen',
    () async {
    final db = await store.database;
    final now = DateTime.utc(2026, 11, 12).toIso8601String();

    final conversationId = await db.insert('assistant_conversations', {
      'title': 'AI conversation',
      'mode': 'learning',
      'created_at': now,
      'updated_at': now,
      'last_message_preview': 'private conversation preview',
    });
    await db.insert('assistant_messages', {
      'conversation_id': conversationId,
      'role': 'user',
      'content': 'private user message',
      'created_at': now,
      'metadata': null,
    });
    await db.insert('tcm_interview_tasks', {
      'conversation_id': conversationId,
      'task_id': 'task-ai-clear-test',
      'status': 'in_progress',
      'state_json': '{"private":"interview snapshot"}',
      'updated_at': now,
    });
    await db.insert('chat_history', {
      'text': 'legacy AI chat content',
      'is_user': 1,
      'timestamp': now,
    });

    await db.insert('bookmarks', {
      'title': 'keep bookmark',
      'content': 'non-AI bookmark content',
      'category': 'classic',
      'source': 'manual',
      'created_at': now,
    });
    await db.insert('diagnosis_history', {
      'meridian': '太阳',
      'pattern': 'sample',
      'formula': 'sample',
      'confidence': 0.0,
      'answers': 'non-AI diagnosis history',
      'created_at': now,
    });
    await db.insert('search_history', {
      'query': 'non-AI search history',
      'timestamp': now,
    });
    await db.insert('user_settings', {
      'key': 'non_ai_setting',
      'value': 'preserve-me',
    });

    await store.clearAllAiConversationData();

    Future<int> countRows(String table) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      );
      return rows.single['count'] as int;
    }

    expect(await countRows('assistant_conversations'), 0);
    expect(await countRows('assistant_messages'), 0);
    expect(await countRows('tcm_interview_tasks'), 0);
    expect(await countRows('chat_history'), 0);

    expect(await countRows('bookmarks'), 1);
    expect(await countRows('diagnosis_history'), 1);
    expect(await countRows('search_history'), 1);
    expect(await countRows('user_settings'), 1);

    await DatabaseHelper.closeTestDatabase();
    DatabaseHelper.configureTestDatabase(
      'ai_clear_boundary_test.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );
    final reopened = await store.database;

    Future<int> reopenedCount(String table) async {
      final rows = await reopened.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      );
      return rows.single['count'] as int;
    }

    expect(await reopenedCount('assistant_conversations'), 0);
    expect(await reopenedCount('assistant_messages'), 0);
    expect(await reopenedCount('tcm_interview_tasks'), 0);
    expect(await reopenedCount('chat_history'), 0);
    expect(await reopenedCount('bookmarks'), 1);
    expect(await reopenedCount('diagnosis_history'), 1);
    expect(await reopenedCount('search_history'), 1);
    expect(await reopenedCount('user_settings'), 1);
    expect(
      (await reopened.query('user_settings')).single['value'],
      'preserve-me',
    );
    },
  );
  test('rolls back every AI table when one table delete fails', () async {
    final db = await store.database;
    final now = DateTime.utc(2026, 11, 12).toIso8601String();
    final conversationId = await db.insert('assistant_conversations', {
      'title': 'rollback test',
      'mode': 'learning',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('assistant_messages', {
      'conversation_id': conversationId,
      'role': 'user',
      'content': 'keep on rollback',
      'created_at': now,
    });
    await db.insert('tcm_interview_tasks', {
      'conversation_id': conversationId,
      'task_id': 'task-ai-clear-rollback',
      'status': 'in_progress',
      'state_json': '{}',
      'updated_at': now,
    });
    await db.insert('chat_history', {
      'text': 'legacy AI chat',
      'is_user': 1,
      'timestamp': now,
    });
    await db.execute('''
      CREATE TRIGGER reject_ai_conversation_delete
      BEFORE DELETE ON assistant_conversations
      BEGIN
        SELECT RAISE(ABORT, 'injected conversation delete failure');
      END
    ''');

    await expectLater(
      store.clearAllAiConversationData(),
      throwsA(anything),
    );

    Future<int> countRows(String table) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      );
      return rows.single['count'] as int;
    }

    expect(await countRows('assistant_conversations'), 1);
    expect(await countRows('assistant_messages'), 1);
    expect(await countRows('tcm_interview_tasks'), 1);
    expect(await countRows('chat_history'), 1);
  });

}
