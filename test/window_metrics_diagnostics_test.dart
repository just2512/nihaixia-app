import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/window_metrics_diagnostics.dart';

void main() {
  testWidgets('logs half-opened hinge geometry and changed window metrics once',
      (tester) async {
    final previousDebugPrint = debugPrint;
    final messages = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(380, 0, 15, 828),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureHalfOpened,
    );
    final innerWindow = MediaQueryData(
      size: const Size(775, 828),
      devicePixelRatio: 2,
      displayFeatures: const [hinge],
      viewInsets: const EdgeInsets.only(bottom: 260),
      viewPadding: const EdgeInsets.only(bottom: 20),
      textScaler: TextScaler.linear(1.5),
    );

    Widget host(MediaQueryData data) => MediaQuery(
          data: data,
          child: const WindowMetricsDiagnostics(child: SizedBox.expand()),
        );

    await tester.pumpWidget(host(innerWindow));

    expect(messages, hasLength(1));
    expect(messages.single, contains('[WINDOW_METRICS]'));
    expect(messages.single, contains('sizeDp=775.0x828.0'));
    expect(messages.single, contains('physicalPx=1550.0x1656.0'));
    expect(messages.single, contains('dpr=2.00'));
    expect(
      messages.single,
      contains('hinge/postureHalfOpened@380.0,0.0,15.0x828.0'),
    );
    expect(messages.single, contains('viewInsets=l=0.0,t=0.0,r=0.0,b=260.0'));
    expect(messages.single, contains('viewPadding=l=0.0,t=0.0,r=0.0,b=20.0'));
    expect(messages.single, contains('textScale=1.50'));

    await tester.pumpWidget(host(innerWindow));
    expect(messages, hasLength(1), reason: 'unchanged metrics are not repeated');

    final outerWindow = innerWindow.copyWith(
      size: const Size(403, 874),
      devicePixelRatio: 3,
      displayFeatures: const [],
      viewInsets: EdgeInsets.zero,
      viewPadding: const EdgeInsets.only(bottom: 24),
      textScaler: TextScaler.linear(1),
    );
    await tester.pumpWidget(host(outerWindow));

    expect(messages, hasLength(2));
    expect(messages.last, contains('sizeDp=403.0x874.0'));
    expect(messages.last, contains('dpr=3.00'));
    expect(messages.last, contains('displayFeatures=[]'));
    expect(messages.last, contains('textScale=1.00'));
  });
}
