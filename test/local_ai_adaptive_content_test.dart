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

  testWidgets('AI interview content is capped and centered on expanded windows', (tester) async {
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
    expect(content.width, 640);
    expect(rect.center.dx, closeTo(420, 1));
  });
}
