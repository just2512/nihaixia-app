import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('README current app version matches the single pubspec version source', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    final pubspecVersion = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    final readmeVersion = RegExp(
      r'当前仓库版本为 `([^ `]+)`',
    ).firstMatch(readme)?.group(1);

    expect(pubspecVersion, isNotNull);
    expect(readmeVersion, pubspecVersion);
  });
}
