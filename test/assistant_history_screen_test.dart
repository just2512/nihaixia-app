import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/assistant_history_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  testWidgets('历史会话可查看，并支持多选删除', (tester) async {
    final store = DatabaseHelper.instance;
    final first = await store.createAssistantConversation(title: '问诊记录甲');
    final second = await store.createAssistantConversation(title: '学习记录乙');
    await store.saveAssistantMessage(
      conversationId: first,
      role: 'user',
      content: '持续两天头痛',
    );
    await store.saveAssistantMessage(
      conversationId: second,
      role: 'user',
      content: '桂枝汤的原文出处',
    );

    await tester.pumpWidget(
      const MaterialApp(home: AssistantHistoryScreen()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('问诊记录甲'), findsOneWidget);
    expect(find.text('学习记录乙'), findsOneWidget);
    expect(find.text('桂枝汤的原文出处'), findsOneWidget);

    await tester.tap(find.byTooltip('批量选择'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('问诊记录甲'));
    await tester.tap(find.text('学习记录乙'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个对话'), findsOneWidget);

    await tester.tap(find.byTooltip('删除所选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('暂无历史对话'), findsOneWidget);
    expect(await store.getAssistantConversations(), isEmpty);
  });
}
