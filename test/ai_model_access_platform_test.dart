import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/ai_model_access_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(yanjiLocalAiChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('sends and confirms the single Native ai_access state', () async {
    final received = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      received.add(call);
      final arguments = call.arguments as Map;
      return <String, Object?>{
        'aiAccessEnabled': arguments['allowed'],
      };
    });

    const platform = MethodChannelAiModelAccessPlatform();
    await platform.setAiAccess(false);
    await platform.setAiAccess(true);

    expect(received.map((call) => call.method), ['setAiAccess', 'setAiAccess']);
    expect(received.map((call) => call.arguments), [
      {'allowed': false},
      {'allowed': true},
    ]);
  });

  test('rejects a Native response that does not confirm the requested state', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return <String, Object?>{'aiAccessEnabled': true};
    });

    expect(
      () => const MethodChannelAiModelAccessPlatform().setAiAccess(false),
      throwsA(isA<AiModelAccessPlatformFailure>()),
    );
  });

  test('rejects a missing Native bridge as unavailable', () async {
    expect(
      () => const MethodChannelAiModelAccessPlatform().setAiAccess(false),
      throwsA(isA<AiModelAccessPlatformFailure>()),
    );
  });
}
