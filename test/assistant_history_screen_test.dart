import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('历史会话可查看，并支持多选删除', (tester) async {
    final rows = <Map<String, Object?>>[
      {
        'id': 1,
        'title': '问诊记录甲',
        'mode': 'consultation',
        'created_at': '2026-11-03T08:00:00.000',
        'updated_at': '2026-11-03T08:10:00.000',
        'last_message_preview': '持续两天头痛',
      },
      {
        'id': 2,
        'title': '学习记录乙',
        'mode': 'learning',
        'created_at': '2026-11-03T08:01:00.000',
        'updated_at': '2026-11-03T08:11:00.000',
        'last_message_preview': '桂枝汤的原文出处',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantHistoryScreen(
          loadConversations: () async => List<Map<String, Object?>>.of(rows),
          deleteConversations: (ids) async {
            rows.removeWhere((row) => ids.contains(row['id']));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('问诊记录甲'), findsOneWidget);
    expect(find.text('学习记录乙'), findsOneWidget);
    expect(find.text('桂枝汤的原文出处'), findsOneWidget);

    await tester.tap(find.byTooltip('批量选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('问诊记录甲'));
    await tester.tap(find.text('学习记录乙'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个对话'), findsOneWidget);

    await tester.tap(find.byTooltip('删除所选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('暂无历史对话'), findsOneWidget);
    expect(rows, isEmpty);
  });
}
