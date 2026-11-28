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
      'nihaisha-atomic-turn-',
    );
    DatabaseHelper.configureTestDatabase(
      'atomic_turn_test.db',
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

  test('persists a successful user and assistant pair in one transaction',
      () async {
    final conversationId = await store.createAssistantConversation();
    await store.saveAssistantTurn(
      conversationId: conversationId,
      userContent: '用户输入',
      assistantContent: '助手回复',
    );

    final messages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(messages, hasLength(2));
    expect(messages.map((row) => row['role']).toList(), ['user', 'assistant']);
    expect(
      messages.map((row) => row['content']).toList(),
      ['用户输入', '助手回复'],
    );
  });

  test('rolls back the user message when assistant insert fails', () async {
    final conversationId = await store.createAssistantConversation();
    final db = await store.database;
    await db.execute('''
      CREATE TRIGGER reject_assistant_turn
      BEFORE INSERT ON assistant_messages
      WHEN NEW.role = 'assistant'
      BEGIN
        SELECT RAISE(ABORT, 'injected assistant insert failure');
      END
    ''');

    await expectLater(
      store.saveAssistantTurn(
        conversationId: conversationId,
        userContent: '本轮用户输入',
        assistantContent: '本轮助手回复',
      ),
      throwsA(anything),
    );

    final messages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(messages, isEmpty);
  });
}
