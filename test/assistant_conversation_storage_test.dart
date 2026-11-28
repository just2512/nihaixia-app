import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/services/tcm_interview_adapter.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
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
    await db.delete('tcm_interview_tasks');
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

    final taskSnapshot = TcmInterviewAdapter().createSnapshot();
    await store.saveTcmInterviewTaskState(
      conversationId: first,
      state: TcmInterviewTaskState(
        taskId: 'delete-task-$first',
        snapshot: taskSnapshot,
        status: 'active',
      ),
    );
    await store.saveTcmInterviewTaskState(
      conversationId: third,
      state: TcmInterviewTaskState(
        taskId: 'delete-task-$third',
        snapshot: taskSnapshot,
        status: 'active',
      ),
    );

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
    expect(
      await store.getTcmInterviewTaskState(conversationId: first),
      isNull,
    );
    expect(
      await store.getTcmInterviewTaskState(conversationId: third),
      isNull,
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


  test('TCM task state survives database connection restart and is deleted with conversation', () async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation(
      mode: 'consultation',
    );
    final adapter = TcmInterviewAdapter();
    adapter.answerTemperature('fever_chills');
    final state = TcmInterviewTaskState(
      taskId: 'task-restart-1',
      snapshot: adapter.createSnapshot(),
      status: 'awaiting_tongue_pulse',
      pendingPromptId: 'tongue_pulse',
      pendingOptions: const ['舌淡红', '舌红'],
      updatedAt: DateTime.utc(2026, 11, 5),
    );
    await store.saveTcmInterviewTaskState(
      conversationId: conversationId,
      state: state,
    );

    final opened = await DatabaseHelper.instance.database;
    await opened.close();
    DatabaseHelper.resetForTest();

    final restored = await DatabaseHelper.instance.getTcmInterviewTaskState(
      conversationId: conversationId,
    );
    expect(restored?.taskId, state.taskId);
    expect(restored?.status, state.status);
    expect(restored?.pendingPromptId, 'tongue_pulse');
    expect(restored?.pendingOptions, state.pendingOptions);
    expect(restored?.snapshot.answers['temperature'], 'fever_chills');

    await store.deleteAssistantConversations([conversationId]);
    expect(
      await store.getTcmInterviewTaskState(conversationId: conversationId),
      isNull,
    );
  });

  test('工具终态、来源与原始参数在 SQLite 连接重启后保持一致', () async {
    final conversationId =
        await DatabaseHelper.instance.createAssistantConversation(
      mode: 'metaphysics',
    );
    await DatabaseHelper.instance.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '五运六气推算执行失败',
      metadata: AssistantMessageMetadata(
        mode: 'metaphysics',
        selectedMode: 'automatic',
        toolId: 'yunqi',
        toolStatus: 'FAILED',
        sourceIds: const ['local-tool:yunqi:v1'],
        toolArguments: const {'date': '2026-11-07'},
      ).encode(),
    );
    await DatabaseHelper.instance.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '用户已取消紫微排盘',
      metadata: AssistantMessageMetadata(
        mode: 'metaphysics',
        selectedMode: 'automatic',
        toolId: 'ziwei',
        toolStatus: 'CANCELLED',
        toolArguments: const {'date': '2000-08-16'},
      ).encode(),
    );

    final opened = await DatabaseHelper.instance.database;
    await opened.close();
    DatabaseHelper.resetForTest();

    final restored = await DatabaseHelper.instance.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(restored, hasLength(2));
    final failed = AssistantMessageMetadata.decode(
      restored[0]['metadata'] as String,
    );
    expect(failed.toolId, 'yunqi');
    expect(failed.toolStatus, 'FAILED');
    expect(failed.toolArguments, const {'date': '2026-11-07'});
    expect(failed.sourceIds, const ['local-tool:yunqi:v1']);

    final cancelled = AssistantMessageMetadata.decode(
      restored[1]['metadata'] as String,
    );
    expect(cancelled.toolId, 'ziwei');
    expect(cancelled.toolStatus, 'CANCELLED');
    expect(cancelled.toolArguments, const {'date': '2000-08-16'});
  });

  test('SessionState message reads return only the newest visible rows in chronological order', () async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation();

    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '第一轮用户输入',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'tool',
      content: 'REASONING_TURN_PENDING',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '第一轮回答',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'system',
      content: '仅展示层系统记录',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '第二轮用户输入',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '第二轮回答',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'tool',
      content: 'TOOL_INVOCATION_TERMINAL',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '第三轮用户输入',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '第三轮回答',
    );

    final bounded = await store.getAssistantMessagesForSessionState(
      conversationId: conversationId,
      limit: 3,
    );

    expect(bounded, hasLength(3));
    expect(
      bounded.map((row) => row['role']).toList(),
      ['assistant', 'user', 'assistant'],
    );
    expect(
      bounded.map((row) => row['content']).toList(),
      ['', '第三轮用户输入', ''],
      reason: 'SessionState reads user text only; assistant body text is not projected',
    );

    // Full-history consumers (history UI and ReasoningTurnLedger) retain the
    // original unrestricted persistence API.
    final allRows = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(allRows, hasLength(9));
    final allVisibleRows = allRows
        .where((row) => row['role'] == 'user' || row['role'] == 'assistant')
        .toList(growable: false);
    expect(
      bounded.map((row) => row['id']).toList(),
      allVisibleRows.skip(allVisibleRows.length - 3).map((row) => row['id']).toList(),
    );
    expect(
      bounded.first['id'] as int,
      lessThan(bounded.last['id'] as int),
      reason: 'bounded reads are returned in chronological order',
    );
  });

  test('SessionState SQL projection bounds message bodies and metadata payloads', () async {
    final store = DatabaseHelper.instance;
    final conversationId = await store.createAssistantConversation();

    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: List<String>.filled(4000, 'u').join(),
      metadata: List<String>.filled(30000, 'm').join(),
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: List<String>.filled(50000, 'a').join(),
      metadata: List<String>.filled(30000, 'n').join(),
    );

    final rows = await store.getAssistantMessagesForSessionState(
      conversationId: conversationId,
      limit: 2,
    );

    await expectLater(
      store.getAssistantMessagesForSessionState(
        conversationId: conversationId,
        limit: AssistantConversationStore.maxSessionStateReadRows + 1,
      ),
      throwsArgumentError,
    );

    expect(rows, hasLength(2));
    expect(rows.first['role'], 'user');
    expect((rows.first['content'] as String).length, 1201);
    expect((rows.first['content'] as String).length, greaterThan(1200));
    expect((rows.first['metadata'] as String).length, 16001);
    expect(rows.last['role'], 'assistant');
    expect(rows.last['content'], '');
    expect((rows.last['metadata'] as String).length, 16001);

    // The persisted history remains complete; only the SessionState projection
    // is bounded.
    final fullHistory = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect((fullHistory.first['content'] as String).length, 4000);
    expect((fullHistory.last['content'] as String).length, 50000);
    expect((fullHistory.first['metadata'] as String).length, 30000);
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
