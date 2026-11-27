import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production code does not call legacy LocalAiService wrappers or open its raw channel',
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

      await for (final entity in Directory('lib').list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final relativePath = entity.path.replaceAll('\\', '/');
        if (relativePath == implementation) continue;

        final source = await entity.readAsString();
        if (serviceImport.hasMatch(source) || serviceType.hasMatch(source)) {
          for (final match in legacyInvocation.allMatches(source)) {
            final line = source.substring(0, match.start).split('\n').length;
            legacyCallSites.add('$relativePath:$line');
          }
        }

        if (rawLocalAiChannel.hasMatch(source)) {
          rawChannelSites.add(relativePath);
        }
      }

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
