import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/chat_screen.dart';

void main() {
  testWidgets('structured diagnosis displays assistant self-report as context only', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatScreen(
          returnResultOnComplete: true,
          initialUserContext: '用户自述：近两天头痛，下午加重。',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已从 AI 助手带入本次用户自述'), findsOneWidget);
    expect(find.textContaining('近两天头痛，下午加重'), findsOneWidget);
    expect(find.textContaining('不自动映射为辨证选项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
