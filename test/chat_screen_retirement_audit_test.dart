import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy ChatScreen has no Dart production references outside its own file', () async {
    final root = Directory.current.path;
    final legacyScreen = 'lib/screens/chat_screen.dart';
    final thisAudit = 'test/chat_screen_retirement_audit_test.dart';
    final legacyReference = RegExp(r'\bChatScreen\b|chat_screen\.dart');
    final references = <String>[];

    await for (final entity in Directory.current.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path
          .replaceFirst('$root${Platform.pathSeparator}', '')
          .replaceAll('\\', '/');
      if (relativePath == legacyScreen || relativePath == thisAudit) continue;
      if (relativePath.startsWith('.dart_tool/') ||
          relativePath.startsWith('build/') ||
          relativePath.startsWith('.git/')) {
        continue;
      }

      final source = await entity.readAsString();
      if (legacyReference.hasMatch(source) || legacyImport.hasMatch(source)) {
        references.add(relativePath);
      }
    }

    references.sort();
    final productionReferences =
        references.where((path) => path.startsWith('lib/')).toList();
    final testReferences =
        references.where((path) => path.startsWith('test/')).toList();
    final otherDartReferences = references
        .where((path) => !path.startsWith('lib/') && !path.startsWith('test/'))
        .toList();

    expect(
      productionReferences,
      isEmpty,
      reason: 'Production Dart files must not import or construct the legacy ChatScreen.',
    );
    expect(
      testReferences,
      ['test/chat_screen_task_resume_test.dart'],
      reason: 'The remaining legacy test dependency must be migrated before deletion.',
    );
    expect(
      otherDartReferences,
      isEmpty,
      reason: 'No other Dart package/tool entry point may depend on the legacy screen.',
    );
  });
}
