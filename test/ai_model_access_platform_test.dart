import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/ai_model_access_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(yanjiLocalAiAccessChannelName);
  late MethodChannelAiModelAccessPlatform platform;
  late List<MethodCall> calls;

  setUp(() {
    platform = MethodChannelAiModelAccessPlatform(channel: channel);
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('enables only after Native confirms the single access state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(call.method, 'setAiModelAccess');
      expect(call.arguments, <String, Object?>{'enabled': true});
      return <String, Object?>{'enabled': true, 'released': false};
    });

    await platform.setEnabled(true);

    expect(calls, hasLength(1));
  });

  test('disabling requires Native resource-release acknowledgement', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(call.arguments, <String, Object?>{'enabled': false});
      return <String, Object?>{'enabled': false, 'released': true};
    });

    await platform.setEnabled(false);

    expect(calls, hasLength(1));
  });

  test('does not accept a false state without resource-release confirmation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async =>
            <String, Object?>{'enabled': false, 'released': false});

    await expectLater(
      platform.setEnabled(false),
      throwsA(isA<AiModelAccessPlatformFailure>()),
    );
  });

  test('rejects missing or mismatched Native acknowledgements', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async =>
            <String, Object?>{'enabled': false, 'released': true});

    await expectLater(
      platform.setEnabled(true),
      throwsA(isA<AiModelAccessPlatformFailure>()),
    );
  });
}
