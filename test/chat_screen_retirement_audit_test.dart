import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy ChatScreen has no production imports or constructor callsites', () {
    final productionFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path.replaceAll('\\', '/')
            != 'lib/screens/chat_screen.dart');
    final importDirective = RegExp(
      r'''^\s*(?:import|export|part)\s+['"][^'"]*chat_screen\.dart['"]''',
      multiLine: true,
    );
    final constructorCall = RegExp(r'\bChatScreen\s*\(');
    final violations = <String>[];

    for (final file in productionFiles) {
      final source = file.readAsStringSync();
      if (importDirective.hasMatch(source) || constructorCall.hasMatch(source)) {
        violations.add(file.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Do not restore a production entry into the retired ChatScreen. '
          'The remaining file and legacy-only tests must not be treated as '
          'proof that it is safe to delete.',
    );
  });
}
