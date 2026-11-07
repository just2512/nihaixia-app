import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy ChatScreen has no production references outside its own file', () {
    final productionFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path.replaceAll('\\', '/')
            != 'lib/screens/chat_screen.dart');
    final legacyReference = RegExp(r'\bChatScreen\b|chat_screen\.dart');
    final violations = <String>[];

    for (final file in productionFiles) {
      final source = file.readAsStringSync();
      if (legacyReference.hasMatch(source)) {
        violations.add(file.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'No production source may import, construct, navigate to, or '
          'otherwise reference the legacy ChatScreen. Keep the legacy file '
          'until its remaining tests and behavior have been migrated.',
    );
  });
}
