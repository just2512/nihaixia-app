import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/ziwuliuzhu_screen.dart';

void main() {
  testWidgets('时辰开穴工具把四种计算结果返回统一 AI 对话', (tester) async {
    String? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => ZiWuLiuZhuScreen(
                      returnResultOnComplete: true,
                      initialDate: DateTime(2026, 11, 4, 10, 30),
                    ),
                  ),
                );
              },
              child: const Text('打开时辰开穴'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开时辰开穴'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回 AI 助手'), findsOneWidget);

    await tester.tap(find.byTooltip('返回 AI 助手'));
    await tester.pumpAndSettle();

    expect(returned, isNotNull);
    expect(returned, contains('中医时辰开穴计算结果'));
    expect(returned, contains('纳子法：'));
    expect(returned, contains('纳甲法：'));
    expect(returned, contains('灵龟八法：'));
    expect(returned, contains('飞腾八法：'));
    expect(returned, contains('2026-11-04 10:30'));
  });
}
