import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const retiredBrandName = String.fromCharCodes([0x6c49, 0x5510, 0x4e2d, 0x533b]);

void main() {
  group('研纪产品品牌身份', () {
    test('Android 与 Flutter 显示名称统一，旧安装身份保持不变', () {
      final pubspec = _read('pubspec.yaml');
      final androidManifest = _read('android/app/src/main/AndroidManifest.xml');
      final androidGradle = _read('android/app/build.gradle.kts');
      final mainDart = _read('lib/main.dart');

      expect(pubspec, contains('name: nihaisha_app'));
      expect(pubspec, contains('description: "研纪 - 中医诊疗全过程辅助学习工具"'));
      expect(androidManifest, contains('android:label="研纪"'));
      expect(mainDart, contains("title: '研纪'"));
      expect(androidGradle, contains('namespace = "com.nihaisha.nihaisha_app"'));
      expect(androidGradle, contains('applicationId = "com.nihaisha.nihaisha_app"'));
    });

    test('Web 页面标题、PWA 名称和描述统一', () {
      final manifest = jsonDecode(_read('web/manifest.json')) as Map<String, dynamic>;
      final indexHtml = _read('web/index.html');

      expect(manifest['name'], '研纪');
      expect(manifest['short_name'], '研纪');
      expect(manifest['description'], contains('研纪'));
      expect(indexHtml, contains('<title>研纪</title>'));
      expect(indexHtml, contains('name="apple-mobile-web-app-title" content="研纪"'));
      expect(indexHtml, isNot(contains('A new Flutter project.')));
      expect(indexHtml, isNot(contains('nihaisha_app')));
    });

    test('关于、导出与 AI 助手使用正式产品名称', () {
      final aboutAndExport = _read('lib/screens/app_dialogs.dart');
      final localAssistant = _read('lib/screens/local_ai_interview_screen.dart');
      final nativeAssistant = _read(
        'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
      );
      final navigationTest = _read('test/home_screen_entry_test.dart');

      expect(aboutAndExport, contains("const Text('研纪'"));
      expect(aboutAndExport, contains('【研纪·收藏导出】'));
      expect(aboutAndExport, contains('—— 来自「研纪」App'));
      expect(localAssistant, contains('【研纪辨证结果】'));
      expect(localAssistant, contains('—— 来自「研纪」App'));
      expect(localAssistant, contains('研纪 AI 助手'));
      expect(nativeAssistant, contains('你是研纪 App 的离线统一助手。'));
      expect(navigationTest, contains('研纪 AI 助手'));
    });

    test('项目介绍、品牌图形及适配文档不再展示旧产品名', () {
      final readme = _read('README.md');
      final maintenance = _read('docs/fork-maintenance-policy.md');
      final adaptive = _read('docs/find-n2-adaptive-layout.md');
      final brandPlan = _read('docs/yanji-editorial-frontend-design-plan.md');
      final positioning = _read('docs/product-positioning-and-boundaries.md');
      final brandIdentity = _read('docs/brand-identity.md');
      final logo = _read('docs/images/logo.svg');
      final banner = _read('docs/images/readme_banner.svg');
      final features = _read('docs/images/readme_features.svg');
      final changelog = _read('CHANGELOG.md');

      for (final content in [
        readme,
        maintenance,
        adaptive,
        brandPlan,
        positioning,
        brandIdentity,
        logo,
        banner,
        features,
      ]) {
        expect(content, contains('研纪'));
        expect(content, isNot(contains(retiredBrandName)));
      }
      expect(banner, contains('>研</text>'));
      expect(banner, contains('>研纪</text>'));
      expect(brandIdentity, contains('唯一对外产品名称：研纪'));
      expect(brandIdentity, contains('Android `applicationId`：`com.nihaisha.nihaisha_app`'));
      expect(changelog.split('\n').first, '# 研纪 App 更新日志（Changelog）');
    });
  });
}
