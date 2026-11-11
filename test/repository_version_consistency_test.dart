import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('README current app version matches pubspec single source of truth', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    final versionMatch = RegExp(
      r'^version:\\s*([0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+)\\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull, reason: 'pubspec.yaml must declare one parseable app version');
    final version = versionMatch!.group(1)!;

    expect(
      readme,
      contains('当前仓库版本为 `$version`'),
      reason: 'README current-version declaration must match pubspec.yaml',
    );
  });
}
