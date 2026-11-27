import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository code does not call retired LocalAiService wrappers; Native legacy text route fails closed',
    () async {
      const implementation = 'lib/services/local_ai_service.dart';
      final serviceImport = RegExp(
        r'''(?:import|export|part)\s+['"][^'"]*local_ai_service\.dart['"]''',
      );
      final serviceType = RegExp(r'\bLocalAiService\b');
      final legacyInvocation = RegExp(
        r'''\b(?:[A-Za-z_$][A-Za-z0-9_$]*|LocalAiService\s*\(\s*\))\s*\.\s*(?:sendMessageWithContextAndTrace|sendMessageWithContext|sendMessageWithTrace|sendMessage|sendImageWithTrace|sendImage|sendAudioWithTrace|sendAudio)\s*\(''',
      );
      final rawLocalAiChannel = RegExp(
        r'''MethodChannel\s*\(\s*['"]com\.nihaisha\.app/local_ai['"]\s*\)''',
      );
      final legacyCallSites = <String>[];
      final rawChannelSites = <String>[];

      for (final root in ['lib', 'test']) {
        await for (final entity in Directory(root).list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;

          final relativePath = entity.path.replaceAll('\\\\', '/');
          if (relativePath == implementation) continue;

          final source = await entity.readAsString();
          if (serviceImport.hasMatch(source) || serviceType.hasMatch(source)) {
            for (final match in legacyInvocation.allMatches(source)) {
              final line = source.substring(0, match.start).split('\\n').length;
              legacyCallSites.add('$relativePath:$line');
            }
          }

          if (root == 'lib' && relativePath != implementation &&
              rawLocalAiChannel.hasMatch(source)) {
            rawChannelSites.add(relativePath);
          }
        }
      }

      final serviceSource = await File(implementation).readAsString();
      for (final method in [
        'Future<String> sendMessage(',
        'Future<String> sendMessageWithTrace(',
        'Future<String> sendMessageWithContext(',
        'Future<String> sendMessageWithContextAndTrace(',
        'Future<String> sendImage(',
        'Future<String> sendImageWithTrace(',
        'Future<String> sendAudio(',
        'Future<String> sendAudioWithTrace(',
      ]) {
        expect(serviceSource, isNot(contains(method)),
            reason: 'Retired LocalAiService wrapper remains: $method');
      }

      final native = await File(
        'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
      ).readAsString();
      final legacyTextStart = native.indexOf('"sendMessage" ->');
      final reasoningTextStart = native.indexOf('"sendReasoningMessage" ->', legacyTextStart);
      expect(legacyTextStart, greaterThanOrEqualTo(0));
      expect(reasoningTextStart, greaterThan(legacyTextStart));
      final legacyTextHandler = native.substring(legacyTextStart, reasoningTextStart);
      expect(legacyTextHandler, contains('STRUCTURED_REASONING_PROTOCOL_REQUIRED'));
      expect(legacyTextHandler, isNot(contains('runAiTask')));
      expect(legacyTextHandler, isNot(contains('sendLocalMessage(')));
      expect(native, isNot(contains('private fun sendLocalMessage(')));

      legacyCallSites.sort();
      rawChannelSites.sort();

      expect(
        legacyCallSites,
        isEmpty,
        reason: 'Use sendReasoningMessage / sendReasoningAttachmentMessage '
            'instead of legacy unstructured LocalAiService methods.',
      );
      expect(
        rawChannelSites,
        isEmpty,
        reason: 'The local AI MethodChannel must be owned by LocalAiService.',
      );
    },
  );
}
