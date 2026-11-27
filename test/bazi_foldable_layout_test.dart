import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/bazi_paipan_screen.dart';

void main() {
  for (final width in [402.0, 840.0]) {
    testWidgets('BaZi input card fits foldable display width $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: BaZiPaipanScreen()),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('bazi-input-card'));
      expect(card, findsOneWidget);
      final cardWidth = tester.getSize(card).width;
      expect(cardWidth, lessThanOrEqualTo(720));
      final yearTop = tester.getTopLeft(find.byKey(const ValueKey('bazi-year-field'))).dy;
      final monthTop = tester.getTopLeft(find.byKey(const ValueKey('bazi-month-field'))).dy;
      final dayTop = tester.getTopLeft(find.byKey(const ValueKey('bazi-day-field'))).dy;
      expect(yearTop, monthTop);
      if (width < 600) {
        expect(dayTop, greaterThan(yearTop));
      } else {
        expect(dayTop, yearTop);
      }
      if (width > 720) {
        expect(cardWidth, closeTo(720, 1));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
