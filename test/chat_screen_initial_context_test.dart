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

  testWidgets('舌脉 UI 只提交 canonical 选项并区分主脉与兼脉', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatScreen(returnResultOnComplete: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('发热 + 怕冷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择舌诊脉诊'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '黄厚'));
    await tester.tap(find.widgetWithText(FilterChip, '淡白'));
    await tester.tap(find.widgetWithText(FilterChip, '数').first);
    final secondaryPulse = find.widgetWithText(FilterChip, '浮').last;
    await tester.ensureVisible(secondaryPulse);
    await tester.pumpAndSettle();
    await tester.tap(secondaryPulse);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.textContaining('苔黄厚'), findsOneWidget);
    expect(find.textContaining('形淡白'), findsOneWidget);
    expect(find.textContaining('脉数'), findsOneWidget);
    expect(find.textContaining('兼脉浮'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
