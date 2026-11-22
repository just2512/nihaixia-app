import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final backtick = String.fromCharCode(96);

  String? valueAfterBacktick(String source, String prefix) {
    final line = source
        .split('\n')
        .firstWhere((item) => item.contains(prefix), orElse: () => '');
    final first = line.indexOf(backtick);
    if (first < 0) return null;
    final second = line.indexOf(backtick, first + 1);
    if (second <= first) return null;
    return line.substring(first + 1, second);
  }

  test('pubspec, README and version policy use one exact product version', () {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    final readme = File('$root/README.md').readAsStringSync();
    final policy = File('$root/docs/versioning-policy.md').readAsStringSync();

    final pubVersion = RegExp(
      r'^version:\s*(\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    final readmeSourceVersion = valueAfterBacktick(readme, '当前源码版本：');
    final readmeCurrentVersion = valueAfterBacktick(readme, '当前仓库版本为');
    final policyVersion = valueAfterBacktick(policy, '**当前项目版本**：');

    expect(pubVersion, isNotNull);
    expect(readmeSourceVersion, pubVersion);
    expect(readmeCurrentVersion, pubVersion);
    expect(policyVersion, pubVersion);
  });

  test('Android build number is above the known shared applicationId maximum', () {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    final policy = File('$root/docs/versioning-policy.md').readAsStringSync();
    final version = RegExp(
      r'^version:\s*\d+\.\d+\.\d+\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    final maximum = valueAfterBacktick(
      policy,
      '**同 applicationId 已知最高 Android versionCode**：',
    );

    expect(version, isNotNull);
    expect(maximum, isNotNull);
    expect(int.parse(version!), greaterThan(int.parse(maximum!)));
  });

  test('the independent version policy preserves local-only original-signing delivery', () {
    final policy = File('$root/docs/versioning-policy.md').readAsStringSync();
    final gradle = File('$root/android/app/build.gradle.kts').readAsStringSync();
    final readme = File('$root/README.md').readAsStringSync();

    expect(policy, contains('本地使用设备当前安装包对应的原签名密钥'));
    expect(policy, contains('不推送发行 Tag'));
    expect(gradle, contains('signingConfig = signingConfigs.getByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(readme, contains('不发布 GitHub Release'));
  });
}
