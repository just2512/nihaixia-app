import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-data-clear-db-');
    DatabaseHelper.configureTestDatabase(
      'ai-clear.db',
      factory: databaseFactoryFfi,
      directoryPath: directory.path,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<int> countRows(String table) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
    return rows.single['count'] as int;
  }

  Future<int> seedConversation() async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.utc(2026, 11, 11).toIso8601String();
    final conversationId = await db.insert('assistant_conversations', {
      'title': '测试会话',
      'mode': 'unified',
      'created_at': now,
      'updated_at': now,
      'last_message_preview': '测试内容',
    });
    await db.insert('assistant_messages', {
      'conversation_id': conversationId,
      'role': 'user',
      'content': '合成测试消息',
      'created_at': now,
      'metadata': null,
    });
    await db.insert('tcm_interview_tasks', {
      'conversation_id': conversationId,
      'task_id': 'test-task-$conversationId',
      'status': 'in_progress',
      'state_json': '{}',
      'updated_at': now,
    });
    return conversationId;
  }

  test('clears all AI conversation tables but preserves non-AI data', () async {
    final db = await DatabaseHelper.instance.database;
    await seedConversation();
    await db.insert('chat_history', {
      'text': 'legacy synthetic chat',
      'is_user': 1,
      'timestamp': DateTime.utc(2026, 11, 11).toIso8601String(),
    });
    await db.insert('user_settings', {'key': 'sentinel', 'value': 'keep'});
    await db.insert('diagnosis_history', {
      'meridian': 'sentinel',
      'pattern': 'keep',
      'formula': null,
      'confidence': null,
      'answers': '{}',
      'created_at': DateTime.utc(2026, 11, 11).toIso8601String(),
    });

    await DatabaseHelper.instance.clearAllAiConversationData();

    expect(await countRows('assistant_messages'), 0);
    expect(await countRows('tcm_interview_tasks'), 0);
    expect(await countRows('assistant_conversations'), 0);
    expect(await countRows('chat_history'), 0);
    expect(await countRows('user_settings'), 1);
    expect(await countRows('diagnosis_history'), 1);
  });

  test('rolls back the entire database clear when one table delete fails',
      () async {
    final db = await DatabaseHelper.instance.database;
    await seedConversation();
    await db.execute('DROP TABLE chat_history');

    await expectLater(
      DatabaseHelper.instance.clearAllAiConversationData(),
      throwsA(anything),
    );

    expect(await countRows('assistant_messages'), 1);
    expect(await countRows('tcm_interview_tasks'), 1);
    expect(await countRows('assistant_conversations'), 1);
  });
}
