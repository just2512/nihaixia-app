import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.configureTestDatabase('assistant_conversation_storage_test.db');
  });

  tearDownAll(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('assistant_messages');
    await db.delete('assistant_conversations');
  });

  test('会话和消息持久化，首条用户消息生成标题', () async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation(
      mode: 'consultation',
    );

    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '最近三天睡眠不好，半夜容易醒',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '具体通常在几点醒来？',
    );

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    expect(conversations.single['id'], conversationId);
    expect(conversations.single['mode'], 'consultation');
    expect(conversations.single['title'], '最近三天睡眠不好，半夜容易醒');
    expect(conversations.single['last_message_preview'], '具体通常在几点醒来？');

    final messages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(messages.map((message) => message['role']).toList(),
        ['user', 'assistant']);
    expect(messages.map((message) => message['content']).toList(),
        ['最近三天睡眠不好，半夜容易醒', '具体通常在几点醒来？']);
  });

  test('支持多选批量删除，且只删除选中的会话及其消息', () async {
    final store = DatabaseHelper.instance;
    final first = await store.createAssistantConversation(title: '问诊');
    final second = await store.createAssistantConversation(title: '学习');
    final third = await store.createAssistantConversation(title: '工具');

    await store.saveAssistantMessage(
      conversationId: first,
      role: 'user',
      content: '第一段会话',
    );
    await store.saveAssistantMessage(
      conversationId: second,
      role: 'user',
      content: '第二段会话',
    );
    await store.saveAssistantMessage(
      conversationId: third,
      role: 'user',
      content: '第三段会话',
    );

    await store.deleteAssistantConversations([first, third, first]);

    final remaining = await store.getAssistantConversations();
    expect(remaining.map((row) => row['id']).toList(), [second]);
    expect(
      await store.getAssistantMessages(conversationId: first),
      isEmpty,
    );
    expect(
      await store.getAssistantMessages(conversationId: third),
      isEmpty,
    );
    expect(
      (await store.getAssistantMessages(conversationId: second)),
      hasLength(1),
    );
  });

  test('拒绝不存在的会话和不支持的消息角色', () async {
    final store = DatabaseHelper.instance;
    await expectLater(
      store.saveAssistantMessage(
        conversationId: -1,
        role: 'user',
        content: 'orphan',
      ),
      throwsA(isA<StateError>()),
    );
    final conversationId = await store.createAssistantConversation();
    await expectLater(
      store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'model',
        content: 'invalid role',
      ),
      throwsArgumentError,
    );
  });

  test('历史列表不显示尚未产生消息的空会话', () async {
    final store = DatabaseHelper.instance;
    final empty = await store.createAssistantConversation(title: '空会话');
    final active = await store.createAssistantConversation(title: '有内容');

    await store.saveAssistantMessage(
      conversationId: active,
      role: 'user',
      content: '请解释少阳病',
    );

    final conversations = await store.getAssistantConversations();
    final ids = conversations.map((row) => row['id']).toSet();
    expect(ids, contains(active));
    expect(ids, isNot(contains(empty)));
    expect(conversations.single['message_count'], 1);
  });


  test('默认历史列表不截断超过 100 条的会话', () async {
    final store = DatabaseHelper.instance;
    for (var index = 0; index < 105; index++) {
      final id = await store.createAssistantConversation(title: '会话 $index');
      await store.saveAssistantMessage(
        conversationId: id,
        role: 'user',
        content: '第 $index 条会话内容',
      );
    }

    final all = await store.getAssistantConversations();
    expect(all, hasLength(105));
    expect(all.first['title'], '会话 104');
    expect(all.last['title'], '会话 0');
    expect(await store.getAssistantConversations(limit: 20), hasLength(20));
  });


}
