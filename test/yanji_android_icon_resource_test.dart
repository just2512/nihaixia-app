import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

String readText(String path) => File(path).readAsStringSync();

void main() {
  group('研纪 Android Launcher 图标资源', () {
    test('Launcher 颜色与 App 现有主题 Token 完全一致', () {
      final appColors = readText('lib/theme/app_colors.dart');
      final palette = readText('lib/theme/yanji_palette.dart');
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

      expect(appColors, contains('primary: YanjiPalette.brandRed'));
      expect(appColors, contains('background: YanjiPalette.coldWhite'));
      expect(foreground, contains('android:fillColor="#D71019"'));
      expect(background, contains('#EBECEE'));
      expect(legacy, contains('#D71019'));
      expect(legacy, contains('#EBECEE'));
      expect(legacyRound, contains('#D71019'));
      expect(legacyRound, contains('#EBECEE'));
      expect(svg, contains('fill="#D71019"'));
      expect(svg, contains('fill="#EBECEE"'));
      expect(palette, contains('static const brandRed = Color(0xFFD71019)'));
      expect(palette, contains('static const coldWhite = Color(0xFFEBECEE)'));


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
        expect(content, isNot(contains('#43594D')));
        expect(content, isNot(contains('#E7E9E4')));

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

    test('旧 API 密度回退 PNG 使用当前品牌红与冷白', () async {
      for (final density in [
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      ]) {
        final bytes = File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        ).readAsBytesSync();
        late final ui.Codec codec;
        try {
          codec = await ui.instantiateImageCodec(bytes);
        } catch (error) {
          fail('$density PNG decode failed: $error');
        }
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(data, isNotNull, reason: '$density PNG must decode');
            final rgba = data!.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );

            bool containsRgb(int red, int green, int blue) {
              for (var i = 0; i < rgba.length; i += 4) {
                if (rgba[i] == red &&
                    rgba[i + 1] == green &&
                    rgba[i + 2] == blue &&
                    rgba[i + 3] == 255) {
                  return true;
                }
              }
              return false;
            }

            expect(
              containsRgb(0xD7, 0x10, 0x19),
              isTrue,
              reason: '$density fallback must include brand red #D71019',
            );
            expect(
              containsRgb(0xEB, 0xEC, 0xEE),
              isTrue,
              reason: '$density fallback must include cold white #EBECEE',
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
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
