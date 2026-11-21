import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/dream_screen.dart';

void main() {
  testWidgets('周公解梦在窄屏和宽屏保留搜索、分类及逐条明确选择入口',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final viewport in [const Size(402, 880), const Size(775, 1024)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(const MaterialApp(home: DreamScreen()));
      await tester.pumpAndSettle();

      expect(find.text('周公解梦'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.byKey(const ValueKey('dream-entry-action_001')), findsOneWidget);
      expect(find.byKey(const ValueKey('dream-ask-ai-action_001')), findsOneWidget);

      final card = tester.widget<Card>(
        find.byKey(const ValueKey('dream-entry-action_001')),
      );
      expect(card.child, isNotNull);

      await tester.enterText(find.byType(TextField), '走路');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dream-ask-ai-action_001')), findsOneWidget);
      expect(find.textContaining('梦见走路'), findsWidgets);
    }
  });
}
