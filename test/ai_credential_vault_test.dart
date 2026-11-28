import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/ai_credential_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(aiCredentialVaultChannelName);
  late MethodChannelAiCredentialVault vault;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    vault = MethodChannelAiCredentialVault(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'save':
          return <String, Object?>{'credentialRef':
            '123e4567-e89b-12d3-a456-426614174000'};
        case 'read':
          return <String, Object?>{'found': true, 'providerId': 'provider-1', 'secret': 'test-secret'};
        case 'delete':
          return <String, Object?>{'deleted': true};
        case 'exists':
          return <String, Object?>{'exists': true};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('saves provider secret and returns opaque credential reference', () async {
    final reference = await vault.save(
      providerId: 'provider-1',
      secret: 'test-secret',
    );

    expect(reference, '123e4567-e89b-12d3-a456-426614174000');
    expect(calls.single.method, 'save');
    expect(calls.single.arguments['providerId'], 'provider-1');
    expect(calls.single.arguments['secret'], 'test-secret');
  });

  test('reads secret only through vault call and returns null when missing',
      () async {
    final entry = await vault.read('123e4567-e89b-12d3-a456-426614174000');
    expect(entry?.providerId, 'provider-1');
    expect(entry?.secret, 'test-secret');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{'found': false};
    });
    expect(
      await vault.read('123e4567-e89b-12d3-a456-426614174000'),
      isNull,
    );
  });

  test('deletes and checks local existence without network APIs', () async {
    await vault.delete('123e4567-e89b-12d3-a456-426614174000');
    expect(
      await vault.exists('123e4567-e89b-12d3-a456-426614174000'),
      isTrue,
    );
    expect(calls.map((call) => call.method), containsAll(['delete', 'exists']));
  });

  test('rejects invalid references before platform invocation', () async {
    await expectLater(
      vault.read('../credential'),
      throwsA(isA<AiCredentialVaultException>()),
    );
    expect(calls, isEmpty);
  });

  test('rejects empty secrets before platform invocation', () async {
    await expectLater(
      vault.save(providerId: 'provider-1', secret: ''),
      throwsA(isA<AiCredentialVaultException>()),
    );
    expect(calls, isEmpty);
  });

  test('maps missing platform plugin to explicit unavailable state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
      vault.exists('123e4567-e89b-12d3-a456-426614174000'),
      throwsA(
        isA<AiCredentialVaultException>().having(
          (error) => error.code,
          'code',
          'CREDENTIAL_VAULT_UNAVAILABLE',
        ),
      ),
    );
  });
}
