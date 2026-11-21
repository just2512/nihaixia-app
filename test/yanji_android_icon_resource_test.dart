import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readText(String path) => File(path).readAsStringSync();

void main() {
  group('研纪 Android Launcher 图标资源', () {
    test('Launcher 颜色与 App 现有主题 Token 完全一致', () {
      final appColors = readText('lib/theme/app_colors.dart');
      final foreground = readText(
        'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      );
      final background = readText(
        'android/app/src/main/res/values/ic_launcher_background.xml',
      );
      final legacy = readText(
        'android/app/src/main/res/mipmap-anydpi/ic_launcher.xml',
      );
      final legacyRound = readText(
        'android/app/src/main/res/mipmap-anydpi/ic_launcher_round.xml',
      );
      final svg = readText('docs/images/logo.svg');

      expect(appColors, contains('primary: const Color(0xFF43594D)'));
      expect(appColors, contains('background: const Color(0xFFE7E9E4)'));
      expect(foreground, contains('android:fillColor="#43594D"'));
      expect(background, contains('#E7E9E4'));
      expect(legacy, contains('#43594D'));
      expect(legacy, contains('#E7E9E4'));
      expect(legacyRound, contains('#43594D'));
      expect(legacyRound, contains('#E7E9E4'));
      expect(svg, contains('fill="#43594D"'));
      expect(svg, contains('fill="#E7E9E4"'));

      for (final content in [
        foreground,
        background,
        legacy,
        legacyRound,
        svg,
      ]) {
        expect(content, isNot(contains('#A93226')));
        expect(content, isNot(contains('#F3EBDD')));
        expect(content, isNot(contains('#B89453')));
      }
    });

    test('Adaptive Icon 普通与圆形入口引用相同的前景和背景', () {
      for (final path in [
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
      ]) {
        final icon = readText(path);
        expect(icon, contains('@color/ic_launcher_background'));
        expect(icon, contains('@drawable/ic_launcher_foreground'));
      }
    });

    test('旧 API 密度回退图标资源仍完整存在', () {
      for (final density in [
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      ]) {
        expect(
          File('android/app/src/main/res/mipmap-$density/ic_launcher.png')
              .existsSync(),
          isTrue,
          reason: '$density launcher PNG must remain available',
        );
      }
    });

    test('应用名称与旧安装身份保持不变', () {
      final manifest = readText('android/app/src/main/AndroidManifest.xml');
      final gradle = readText('android/app/build.gradle.kts');

      expect(manifest, contains('android:label="研纪"'));
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
      expect(gradle, contains('namespace = "com.nihaisha.nihaisha_app"'));
      expect(gradle, contains('applicationId = "com.nihaisha.nihaisha_app"'));
    });
  });
}
