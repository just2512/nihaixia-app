import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  const fileName = 'assistant_invocation_ledger_v7.db';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'nihaixia-invocation-ledger-',
    );
    final legacyPath = p.join(tempDirectory.path, fileName);
    final legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE assistant_conversations(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              mode TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              last_message_preview TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE assistant_messages(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              conversation_id INTEGER NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at TEXT NOT NULL,
              metadata TEXT,
              FOREIGN KEY(conversation_id) REFERENCES assistant_conversations(id)
            )
          ''');
          await db.execute(
            'CREATE INDEX assistant_messages_conversation_idx ON assistant_messages(conversation_id, id)',
          );
        },
      ),
    );
    await legacy.close();

    DatabaseHelper.configureTestDatabase(
      fileName,
      factory: databaseFactoryFfi,
      directoryPath: tempDirectory.path,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    await tempDirectory.delete(recursive: true);
  });

  test('upgrades v7 transcript schema with unique invocation claims and preserves preview', () async {
    final store = DatabaseHelper.instance;
    final database = await store.database;
    final version = await database.getVersion();
    expect(version, 8);

    final columns = await database.rawQuery('PRAGMA table_info(assistant_messages)');
    expect(columns.any((column) => column['name'] == 'invocation_key'), isTrue);

    final conversationId = await store.createAssistantConversation(mode: 'tools');
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '请计算三两换算',
    );
    final before = await store.getAssistantConversations();
    final previewBefore = before.single['last_message_preview'];

    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'tool',
      content: 'TOOL_INVOCATION_CLAIMED',
      metadata: '{"kind":"CLAIMED"}',
      invocationKey: 'request-1:claim',
    );
    final after = await store.getAssistantConversations();
    expect(after.single['last_message_preview'], previewBefore);

    final opened = await store.database;
    await opened.close();
    DatabaseHelper.resetForTest();

    final restored = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(restored, hasLength(2));
    expect(restored.last['role'], 'tool');
    expect(restored.last['invocation_key'], 'request-1:claim');

    await expectLater(
      store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'tool',
        content: 'DUPLICATE_CLAIM',
        invocationKey: 'request-1:claim',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('invocation keys are restricted to hidden tool-role messages', () async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation(mode: 'tools');
    expect(
      () => store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'assistant',
        content: 'not a ledger event',
        invocationKey: 'request-2:claim',
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'tool',
        content: 'empty key',
        invocationKey: ' ',
      ),
      throwsArgumentError,
    );
  });
}
