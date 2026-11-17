// 五运六气图表绘制文字缩放回归测试。
//
// 这些图通过 CustomPainter/TextPainter 绘制标签，不经过普通 Text widget。
// 测试直接捕获 CustomPaint 输出，确认 MediaQuery 的 200% 字号设置确实影响图像。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';

Future<Uint8List> _captureChart({
  required WidgetTester tester,
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF43594D),
          brightness: Brightness.light,
        ),
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
            key: const ValueKey('chart-capture'),
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

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('chart-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (byteData == null) {
    throw StateError('Unable to capture chart pixels for text-scale regression.');
  }
  return byteData.buffer.asUint8List();
}

Future<void> _expectChartRespondsTo200Percent(
  WidgetTester tester, {
  required String chartName,
  required Widget Function(YunQiChartData data) builder,
}) async {
  final normal = await _captureChart(
    tester: tester,
    textScale: 1,
    builder: builder,
  );
  final enlarged = await _captureChart(
    tester: tester,
    textScale: 2,
    builder: builder,
  );

  expect(
    enlarged,
    isNot(equals(normal)),
    reason: '$chartName 的 CustomPainter 输出必须响应 MediaQuery 200% 字号，不能沿用固定字号',
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('五行图的绘制标签响应 200% 字号', (tester) async {
    await _expectChartRespondsTo200Percent(
      tester,
      chartName: '五行图',
      builder: (data) => WuxingChart(data: data),
    );
  });

  testWidgets('五运图的绘制标签响应 200% 字号', (tester) async {
    await _expectChartRespondsTo200Percent(
      tester,
      chartName: '五运图',
      builder: (data) => WuyunChart(data: data),
    );
  });

  testWidgets('六气图的绘制标签响应 200% 字号', (tester) async {
    await _expectChartRespondsTo200Percent(
      tester,
      chartName: '六气图',
      builder: (data) => LiuqiChart(data: data),
    );
  });
}
