import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_history_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();


  testWidgets('点击历史会话将会话 ID 返回给主对话以继续会话', (tester) async {
    final rows = [
      {
        'id': 27,
        'title': '可继续的问诊',
        'mode': 'consultation',
        'created_at': '2026-11-03T08:00:00.000',
        'updated_at': '2026-11-03T08:10:00.000',
        'last_message_preview': '继续追问脉象',
      },
    ];
    int? resumedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Text('恢复会话 ID：${resumedId ?? '无'}'),
                ElevatedButton(
                  onPressed: () async {
                    final id = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) => AssistantHistoryScreen(
                          loadConversations: () async =>
                              List<Map<String, Object?>>.from(rows),
                          deleteConversations: (_) async {},
                        ),
                      ),
                    );
                    resumedId = id;
                  },
                  child: const Text('打开历史'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('可继续的问诊'));
    await tester.pumpAndSettle();

    expect(resumedId, 27);
  });

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

  testWidgets('历史对话标题与摘要在402/775dp和200%字号下自然排版',
      (tester) async {
    const longTitle = '这是一条用于验证大字号下自然换行的较长历史对话标题';
    const longPreview = '这段摘要用于检查历史对话列表在窄屏及大字号时是否仍然可读。'
        '内容应随文字缩放自然换行，不应被固定单行布局强制截断。';
    final rows = [
      {
        'id': 71,
        'title': longTitle,
        'mode': 'learning',
        'created_at': '2026-11-03T08:00:00.000',
        'updated_at': '2026-11-03T08:10:00.000',
        'last_message_preview': longPreview,
      },
    ];

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(brightness),
              extensions: [
                brightness == Brightness.dark ? AppColors.dark : AppColors.light,
              ],
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(2),
              ),
              child: AssistantHistoryScreen(
                loadConversations: () async =>
                    List<Map<String, Object?>>.from(rows),
                deleteConversations: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final title = tester.widget<Text>(find.text(longTitle));
        expect(title.maxLines, isNull,
            reason: '历史标题应自然换行，而不是固定单行截断');
        expect(find.text(longPreview), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '${brightness.name} / ${width.toInt()}dp / 200% 历史列表不应溢出');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
