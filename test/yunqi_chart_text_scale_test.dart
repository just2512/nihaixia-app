// 五运六气图表 CustomPainter 的文字缩放回归测试。
//
// 图表标签由 TextPainter 绘制。改变 MediaQuery TextScaler 后，绘制器必须持有新的
// 缩放状态并请求重绘；否则页面即使处于 200% 字号，图内标签仍保持原字号。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';

final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF43594D),
  brightness: Brightness.light,
);

Future<CustomPainter> _pumpChart(
  WidgetTester tester, {
  required double textScale,
  required Widget Function(YunQiChartData data) builder,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 420);
  tester.view.displayFeatures = const [];
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDisplayFeatures);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: _lightColorScheme,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 378,
            height: 380,
            child: builder(YunQiChartData.of(DateTime(2026, 10, 9))),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
}

Future<void> _expectPainterTracksTextScale(
  WidgetTester tester, {
  required String chartName,
  required Widget Function(YunQiChartData data) builder,
}) async {
  final normal = await _pumpChart(
    tester,
    textScale: 1,
    builder: builder,
  );
  final enlarged = await _pumpChart(
    tester,
    textScale: 2,
    builder: builder,
  );

  expect(
    enlarged.shouldRepaint(normal),
    isTrue,
    reason: '$chartName 的 painter 必须感知 100% → 200% 字号变化并请求重绘',
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('五行图 painter 感知 200% 字号', (tester) async {
    await _expectPainterTracksTextScale(
      tester,
      chartName: '五行图',
      builder: (data) => WuxingChart(data: data),
    );
  });

  testWidgets('五运图 painter 感知 200% 字号', (tester) async {
    await _expectPainterTracksTextScale(
      tester,
      chartName: '五运图',
      builder: (data) => WuyunChart(data: data),
    );
  });

  testWidgets('六气图 painter 感知 200% 字号', (tester) async {
    await _expectPainterTracksTextScale(
      tester,
      chartName: '六气图',
      builder: (data) => LiuqiChart(data: data),
    );
  });
}
