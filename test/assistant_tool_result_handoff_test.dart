import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';

void main() {
  testWidgets('五运六气工具可把实际推算结果返回统一助手', (tester) async {
    String? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const YunQiScreen(returnResultOnComplete: true),
                  ),
                );
              },
              child: const Text('打开五运六气'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开五运六气'));
    await tester.pumpAndSettle();
    expect(find.text('将本次推算结果带回助手对话'), findsOneWidget);

    await tester.tap(find.text('将本次推算结果带回助手对话'));
    await tester.pumpAndSettle();

    expect(returned, isNotNull);
    expect(returned, contains('推算日期：'));
    expect(returned, contains('岁运：'));
    expect(returned, contains('司天：'));
    expect(returned, contains('在泉：'));
    expect(returned, contains('口径：'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('从普通工具入口打开时不显示助手专用返回操作', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: YunQiScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('将本次推算结果带回助手对话'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
