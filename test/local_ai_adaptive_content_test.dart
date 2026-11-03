import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

class _ReadyLocalAiService extends LocalAiService {
  static const status = LocalAiModelStatus(
    installed: true,
    fileExists: true,
    ready: true,
    modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
    expectedSizeBytes: 3659530240,
    backend: 'cpu',
  );

  @override
  Future<LocalAiModelStatus> getStatus() async => status;
}

void main() {
  testWidgets('AI interview content is full-width on compact windows', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(service: _ReadyLocalAiService()),
      ),
    );
    await tester.pumpAndSettle();

    final content = tester.getSize(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    expect(content.width, 402);
  });

  testWidgets('AI interview uses expanded window width up to the content cap', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(840, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(service: _ReadyLocalAiService()),
      ),
    );
    await tester.pumpAndSettle();

    final contentFinder = find.byKey(const ValueKey('local-ai-content-width'));
    final content = tester.getSize(contentFinder);
    final rect = tester.getRect(contentFinder);
    expect(content.width, 840);
    expect(rect.center.dx, closeTo(420, 1));
  });

  testWidgets('AI interview scaffold stays inside one panel beside a vertical hinge', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(service: _ReadyLocalAiService()),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.getRect(find.byType(Scaffold));
    final content = tester.getRect(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    expect(scaffold.left, 0);
    expect(scaffold.right, lessThanOrEqualTo(388));
    expect(content.right, lessThanOrEqualTo(388));
    expect(content.width, 388);
  });

  testWidgets('AI interview uses the full inner display at a zero-width flat fold', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(service: _ReadyLocalAiService()),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.getRect(find.byType(Scaffold));
    final content = tester.getRect(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    expect(scaffold.left, 0);
    expect(scaffold.right, 800);
    expect(content.width, 800);
    expect(content.right, 800);
  });

  testWidgets('AI interview keeps full width when fold posture is unknown', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.unknown,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(service: _ReadyLocalAiService()),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.getRect(find.byType(Scaffold));
    final content = tester.getRect(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    expect(scaffold.right, 800);
    expect(content.left, 0);
    expect(content.right, 800);
    expect(content.width, 800);
  });

  testWidgets('AI interview route stays on the originating right panel beside a vertical hinge', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: _ReadyLocalAiService(),
          preferredAnchorPoint: const Offset(600, 450),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.getRect(find.byType(Scaffold));
    final content = tester.getRect(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    expect(scaffold.left, greaterThanOrEqualTo(412));
    expect(scaffold.right, 800);
    expect(content.left, greaterThanOrEqualTo(412));
    expect(content.right, 800);
    expect(content.width, 388);
  });

  testWidgets('AI interview keeps controls usable at 200% text scale on outer screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2.0),
          ),
          child: child!,
        ),
        home: LocalAiInterviewScreen(service: _ReadyLocalAiService()),
      ),
    );
    await tester.pumpAndSettle();

    final content = tester.getRect(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    final input = tester.getRect(find.byType(TextField));
    expect(content.width, 402);
    expect(input.width, greaterThan(80));
    expect(input.left, greaterThanOrEqualTo(content.left));
    expect(input.right, lessThanOrEqualTo(content.right));
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI interview keeps controls inside the active inner panel at 200% text scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2.0),
          ),
          child: child!,
        ),
        home: LocalAiInterviewScreen(
          service: _ReadyLocalAiService(),
          preferredAnchorPoint: const Offset(600, 450),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = tester.getRect(
      find.byKey(const ValueKey('local-ai-content-width')),
    );
    final input = tester.getRect(find.byType(TextField));
    expect(content.left, greaterThanOrEqualTo(412));
    expect(content.right, 800);
    expect(content.width, 388);
    expect(input.width, greaterThan(80));
    expect(input.left, greaterThanOrEqualTo(content.left));
    expect(input.right, lessThanOrEqualTo(content.right));
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
