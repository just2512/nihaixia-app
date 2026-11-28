import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

String readText(String path) => File(path).readAsStringSync();

void expectCenteredSafeZone(String source, String resourceName) {
  final groupMatch = RegExp(r'<group\b([^>]*)>([\s\S]*?)</group>').firstMatch(source);
  expect(groupMatch, isNotNull, reason: '$resourceName must wrap foreground paths in a transform group');
  final attributes = groupMatch!.group(1)!;
  expect(attributes, contains('android:scaleX="0.75"'), reason: resourceName);
  expect(attributes, contains('android:scaleY="0.75"'), reason: resourceName);
  expect(attributes, contains('android:pivotX="54"'), reason: resourceName);
  expect(attributes, contains('android:pivotY="54"'), reason: resourceName);

  final pathMatches = RegExp(
    r'android:fillColor="#D71019"[^>]*android:pathData="([^"]+)"',
  ).allMatches(groupMatch.group(2)!);
  expect(pathMatches, isNotEmpty, reason: '$resourceName must contain red foreground paths');
  final xs = <double>[];
  final ys = <double>[];
  for (final match in pathMatches) {
    final numbers = RegExp(r'-?(?:\d+(?:\.\d*)?|\.\d+)')
        .allMatches(match.group(1)!)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    expect(numbers.length.isEven, isTrue, reason: '$resourceName path coordinates must be x/y pairs');
    for (var i = 0; i < numbers.length; i += 2) {
      xs.add(numbers[i]);
      ys.add(numbers[i + 1]);
    }
  }

  double scale(double value) => 54 + (value - 54) * 0.75;
  final left = scale(xs.reduce((a, b) => a < b ? a : b));
  final right = scale(xs.reduce((a, b) => a > b ? a : b));
  final top = scale(ys.reduce((a, b) => a < b ? a : b));
  final bottom = scale(ys.reduce((a, b) => a > b ? a : b));
  // Conservative bounds include quadratic Bézier control points.
  expect(left, greaterThanOrEqualTo(21), reason: '$resourceName exceeds left adaptive safe-zone edge');
  expect(right, lessThanOrEqualTo(87), reason: '$resourceName exceeds right adaptive safe-zone edge');
  expect(top, greaterThanOrEqualTo(21), reason: '$resourceName exceeds top adaptive safe-zone edge');
  expect(bottom, lessThanOrEqualTo(87), reason: '$resourceName exceeds bottom adaptive safe-zone edge');
}

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

    test('Adaptive Icon 与 API 24–25 矢量回退的前景均处于 66x66 安全区', () {
      final resources = {
        'adaptive foreground': readText(
          'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
        ),
        'API 24–25 regular fallback': readText(
          'android/app/src/main/res/mipmap-anydpi/ic_launcher.xml',
        ),
        'API 24–25 round fallback': readText(
          'android/app/src/main/res/mipmap-anydpi/ic_launcher_round.xml',
        ),
      };
      for (final entry in resources.entries) {
        expectCenteredSafeZone(entry.value, entry.key);
      }

      final svg = readText('docs/images/logo.svg');
      expect(
        svg,
        contains('transform="translate(13.5 13.5) scale(0.75)"'),
        reason: 'SVG brand master must use the same centered 0.75 scale',
      );
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
          late final ui.FrameInfo frame;
          try {
            frame = await codec.getNextFrame();
          } catch (error) {
            fail('$density PNG frame decode failed: $error');
          }
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
            int? minRedX;
            int? minRedY;
            int? maxRedX;
            int? maxRedY;
            for (var y = 0; y < frame.image.height; y++) {
              for (var x = 0; x < frame.image.width; x++) {
                final offset = (y * frame.image.width + x) * 4;
                final red = rgba[offset];
                final green = rgba[offset + 1];
                final blue = rgba[offset + 2];
                if (rgba[offset + 3] > 240 &&
                    red > green + 80 &&
                    red > blue + 80) {
                  minRedX = minRedX == null || x < minRedX ? x : minRedX;
                  minRedY = minRedY == null || y < minRedY ? y : minRedY;
                  maxRedX = maxRedX == null || x > maxRedX ? x : maxRedX;
                  maxRedY = maxRedY == null || y > maxRedY ? y : maxRedY;
                }
              }
            }
            expect(minRedX, isNotNull, reason: '$density must contain the red mark');
            final safeMin = frame.image.width * (21 / 108);
            final safeMax = frame.image.width * (87 / 108);
            expect(minRedX!.toDouble(), greaterThanOrEqualTo(safeMin - 0.5),
                reason: '$density PNG exceeds left safe-zone edge');
            expect((maxRedX! + 1).toDouble(), lessThanOrEqualTo(safeMax + 0.5),
                reason: '$density PNG exceeds right safe-zone edge');
            expect(minRedY!.toDouble(), greaterThanOrEqualTo(safeMin - 0.5),
                reason: '$density PNG exceeds top safe-zone edge');
            expect((maxRedY! + 1).toDouble(), lessThanOrEqualTo(safeMax + 0.5),
                reason: '$density PNG exceeds bottom safe-zone edge');
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
