import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/ai_model_access_platform.dart';
import 'package:nihaisha_app/licensing/license_platform.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/yanji_status_badge.dart';
import 'package:nihaisha_app/widgets/license_activation_settings_section.dart';

class _FakeAiModelAccessPlatform implements AiModelAccessPlatform {
  bool? currentState;
  @override
  Future<void> setAiAccess(bool allowed) async {
    currentState = allowed;
  }
}

ThemeData _yanjiTestTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: AppColors.colorSchemeFor(Brightness.light),
  extensions: <ThemeExtension<dynamic>>[AppColors.light],
);

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
      verifier: LicenseVerifier(keyRing: LicenseKeyRing(keys: const [])),
      aiModelAccessPlatform: _FakeAiModelAccessPlatform(),
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
        theme: _yanjiTestTheme(),
        home: Scaffold(
          body: LicenseActivationSettingsSection(entitlementService: service),
        ),
      ),
    );

    expect(find.text('研纪专业版'), findsOneWidget);
    expect(find.text('未激活 · 免费功能可正常使用'), findsOneWidget);
    expect(find.byType(YanjiStatusBadge), findsOneWidget);
    expect(find.text('未授权'), findsOneWidget);
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

  testWidgets('200% 字体缩放和窄屏下授权状态仍完整显示且不溢出',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);

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
      verifier: LicenseVerifier(keyRing: LicenseKeyRing(keys: const [])),
      aiModelAccessPlatform: _FakeAiModelAccessPlatform(),
    );
    await service.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: _yanjiTestTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            devicePixelRatio: 1,
            textScaler: TextScaler.linear(2.0),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LicenseActivationSettingsSection(
                entitlementService: service,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(Scaffold)), const Size(360, 800));
    expect(find.byType(YanjiStatusBadge), findsOneWidget);
    expect(find.text('未授权'), findsOneWidget);
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
      verifier: LicenseVerifier(keyRing: LicenseKeyRing(keys: const [])),
      aiModelAccessPlatform: _FakeAiModelAccessPlatform(),
    );
    await service.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: _yanjiTestTheme(),
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
