import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/widgets/local_ai_backend_settings_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.nihaisha.app/local_ai');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, Object?> modelStatus({
    String preferredBackend = 'gpu',
    String backend = 'not_loaded',
    bool ready = false,
  }) =>
      <String, Object?>{
        'installed': true,
        'fileExists': true,
        'hashVerified': true,
        'ready': ready,
        'modelPath': '/app/files/ai_models/gemma-4-E4B-it.litertlm',
        'sizeBytes': 3659530240,
        'expectedSizeBytes': 3659530240,
        'backend': backend,
        'preferredBackend': preferredBackend,
      };

  setUp(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows both backend choices and the actual Native backend',
      (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => modelStatus(
        preferredBackend: 'cpu',
        backend: 'cpu',
        ready: true,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalAiBackendSettingsTile()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GPU'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('当前实际运行：CPU'), findsOneWidget);
  });

  testWidgets('selecting CPU persists the preference and rebuilds the model',
      (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getModelStatus') {
        return modelStatus(
          preferredBackend: 'gpu',
          backend: 'gpu',
          ready: true,
        );
      }
      if (call.method == 'setBackendPreference') {
        return modelStatus(
          preferredBackend: 'cpu',
          backend: 'cpu',
          ready: true,
        );
      }
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalAiBackendSettingsTile()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CPU'));
    await tester.pumpAndSettle();

    expect(
      calls.map((call) => call.method),
      containsAllInOrder(['getModelStatus', 'setBackendPreference']),
    );
    expect(calls.last.arguments, <String, Object?>{'backend': 'cpu'});
    expect(find.text('当前实际运行：CPU'), findsOneWidget);
  });

  testWidgets('after a failed switch the user can select the other backend',
      (tester) async {
    final calls = <MethodCall>[];
    var preference = 'gpu';

    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getModelStatus') {
        return modelStatus(preferredBackend: preference);
      }
      if (call.method == 'setBackendPreference') {
        final requested = call.arguments['backend'] as String;
        preference = requested;
        if (requested == 'cpu') {
          throw PlatformException(
            code: 'LOCAL_AI_ERROR',
            message: 'CPU 初始化失败',
          );
        }
        return modelStatus(preferredBackend: preference);
      }
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalAiBackendSettingsTile()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CPU'));
    await tester.pumpAndSettle();

    expect(find.textContaining('可选择另一后端后重试'), findsOneWidget);
    expect(calls.last.method, 'getModelStatus');

    await tester.tap(find.text('GPU'));
    await tester.pumpAndSettle();

    expect(calls.last.method, 'setBackendPreference');
    expect(calls.last.arguments, <String, Object?>{'backend': 'gpu'});
    expect(find.textContaining('可选择另一后端后重试'), findsNothing);
  });

  testWidgets('shows a retry action when the runtime fell back from GPU to CPU',
      (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getModelStatus') {
        return modelStatus(
          preferredBackend: 'gpu',
          backend: 'cpu',
          ready: true,
        );
      }
      if (call.method == 'setBackendPreference') {
        return modelStatus(
          preferredBackend: 'gpu',
          backend: 'gpu',
          ready: true,
        );
      }
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalAiBackendSettingsTile()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('所选：GPU；当前实际运行：CPU（已回退）'), findsOneWidget);
    await tester.tap(find.text('重新尝试 GPU'));
    await tester.pumpAndSettle();

    expect(calls.last.method, 'setBackendPreference');
    expect(calls.last.arguments, <String, Object?>{'backend': 'gpu'});
  });
}
