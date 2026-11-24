import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';
import 'support/fake_ai_model_access_platform.dart';
import 'package:nihaisha_app/widgets/license_activation_settings_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(yanjiLicenseChannelName);
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows the actual service state and creates a key only after activation tap',
      (tester) async {
    final publicKey = base64UrlEncode(List<int>.filled(32, 7)).replaceAll('=', '');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'readLicenseToken':
          return <String, Object?>{'token': null};
        case 'getDeviceKey':
          throw PlatformException(code: 'keyMissing');
        case 'createDeviceKeyForActivation':
          return <String, Object?>{
            'publicKeySpkiBase64Url': 'MAEAAQ',
            'publicKeySha256': publicKey,
            'securityLevel': 'TRUSTED_ENVIRONMENT',
            'strongBoxFallback': false,
          };
        case 'signActivationRequest':
          expect(call.arguments, contains('payloadBase64Url'));
          return <String, Object?>{'signatureBase64Url': 'MEUCIQDsignature'};
        default:
          throw PlatformException(code: 'unexpectedMethod', message: call.method);
      }
    });

    final service = EntitlementService(
      platform: MethodChannelLicensePlatform(channel: channel),
      aiModelAccessPlatform: FakeAiModelAccessPlatform(),
      verifier: LicenseVerifier(keyRing: LicenseKeyRing(keys: const [])),
    );
    await service.initialize();

    expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
    expect(calls.map((call) => call.method), ['readLicenseToken']);
    expect(
      calls.any((call) => call.method == 'createDeviceKeyForActivation'),
      isFalse,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LicenseActivationSettingsSection(entitlementService: service),
        ),
      ),
    );

    expect(find.text('研纪专业版'), findsOneWidget);
    expect(find.text('未激活 · 免费功能可正常使用'), findsOneWidget);
    expect(find.text('生成设备激活申请'), findsOneWidget);

    await tester.tap(find.text('生成设备激活申请'));
    await tester.pumpAndSettle();

    expect(find.textContaining('YANJIR1.'), findsOneWidget);
    expect(
      calls.map((call) => call.method),
      ['readLicenseToken', 'getDeviceKey', 'createDeviceKeyForActivation', 'signActivationRequest'],
    );
    expect(tester.takeException(), isNull);
    service.dispose();
  });

  testWidgets('does not write an invalid pasted token or create a device key', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'readLicenseToken') {
        return <String, Object?>{'token': null};
      }
      throw PlatformException(code: 'unexpectedMethod', message: call.method);
    });

    final service = EntitlementService(
      platform: MethodChannelLicensePlatform(channel: channel),
      aiModelAccessPlatform: FakeAiModelAccessPlatform(),
      verifier: LicenseVerifier(keyRing: LicenseKeyRing(keys: const [])),
    );
    await service.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LicenseActivationSettingsSection(entitlementService: service),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'not-a-valid-YANJI1-token');
    await tester.tap(find.text('验证并安装授权'));
    await tester.pumpAndSettle();

    expect(
      calls.any((call) => call.method == 'writeLicenseTokenAfterVerification'),
      isFalse,
    );
    expect(
      calls.any((call) => call.method == 'createDeviceKeyForActivation'),
      isFalse,
    );
    expect(service.snapshot.status, EntitlementServiceStatus.unlicensed);
    expect(tester.takeException(), isNull);
    service.dispose();
  });

}
