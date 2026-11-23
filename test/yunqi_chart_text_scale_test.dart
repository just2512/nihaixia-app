// 五运六气图表 CustomPainter 的文字缩放回归测试。
// 同时验证 painter 的重绘决策和最终像素输出，不能只证明 shouldRepaint 被触发。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';

final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF43594D),
  brightness: Brightness.light,
);

class _CapturedChart {
  const _CapturedChart({required this.painter, required this.pixels});

  final CustomPainter painter;
  final Uint8List pixels;
}

Future<_CapturedChart> _pumpChart(
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
          child: RepaintBoundary(
            key: const ValueKey('yunqi-chart-area'),
            child: SizedBox(
              width: 378,
              height: 380,
              child: builder(YunQiChartData.of(DateTime(2026, 10, 9))),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final chartPainters = tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('yunqi-chart-area')),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((widget) => widget.painter)
      .whereType<CustomPainter>()
      .toList();
  expect(chartPainters, hasLength(1), reason: '每张图应只读取自身的 CustomPainter');

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('yunqi-chart-area')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (byteData == null) {
    throw StateError('Unable to capture chart pixels for text-scale regression.');
  }

  return _CapturedChart(
    painter: chartPainters.single,
    pixels: byteData.buffer.asUint8List(),
  );
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
    enlarged.painter.shouldRepaint(normal.painter),
    isTrue,
    reason: '$chartName 的 painter 必须感知 100% → 200% 字号变化并请求重绘',
  );
  expect(
    enlarged.pixels,
    isNot(equals(normal.pixels)),
    reason: '$chartName 的最终 CustomPaint 像素必须随 100% → 200% 字号改变，不能只触发空重绘',
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
