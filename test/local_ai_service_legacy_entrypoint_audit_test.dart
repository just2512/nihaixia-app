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

          final relativePath = entity.path.replaceAll('\\', '/');
          if (relativePath == implementation) continue;

          final source = await entity.readAsString();
          if (serviceImport.hasMatch(source) || serviceType.hasMatch(source)) {
            for (final match in legacyInvocation.allMatches(source)) {
              final line = source.substring(0, match.start).split('\n').length;
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
      final legacyImageStart = native.indexOf('"sendImage" ->');
      final legacyAudioStart = native.indexOf('"sendAudio" ->', legacyImageStart);
      final legacyTextStart = native.indexOf('"sendMessage" ->', legacyAudioStart);
      final reasoningTextStart = native.indexOf('"sendReasoningMessage" ->', legacyTextStart);
      expect(legacyImageStart, greaterThanOrEqualTo(0));
      expect(legacyAudioStart, greaterThan(legacyImageStart));
      expect(legacyTextStart, greaterThan(legacyAudioStart));
      expect(reasoningTextStart, greaterThan(legacyTextStart));

      final legacyImageHandler = native.substring(legacyImageStart, legacyAudioStart);
      final legacyAudioHandler = native.substring(legacyAudioStart, legacyTextStart);
      final legacyTextHandler = native.substring(legacyTextStart, reasoningTextStart);
      expect(legacyImageHandler, contains('STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED'));
      expect(legacyImageHandler, isNot(contains('runAiTask')));
      expect(legacyImageHandler, isNot(contains('sendLocalImage(')));
      expect(legacyAudioHandler, contains('STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED'));
      expect(legacyAudioHandler, isNot(contains('runAiTask')));
      expect(legacyAudioHandler, isNot(contains('sendLocalAudio(')));
      expect(legacyTextHandler, contains('STRUCTURED_REASONING_PROTOCOL_REQUIRED'));
      expect(legacyTextHandler, isNot(contains('runAiTask')));
      expect(legacyTextHandler, isNot(contains('sendLocalMessage(')));
      expect(native, isNot(contains('private fun sendLocalMessage(')));
      expect(native, isNot(contains('private fun sendLocalImage(')));
      expect(native, isNot(contains('private fun sendLocalAudio(')));

      // Every live model-invoking MethodChannel route must opt into the
      // shared runAiTask authorization check. Old sendMessage/sendImage/
      // sendAudio routes are intentionally excluded because they fail closed.
      const modelInferenceRoutes = [
        'loadModel',
        'understandTcmInterviewAnswer',
        'extractSymptoms',
        'resolveAssistantIntent',
        'extractBaziSlots',
        'sendReasoningMessage',
        'sendReasoningAttachmentMessage',
        'restoreConversation',
      ];
      for (final method in modelInferenceRoutes) {
        final routeStart = native.indexOf('"$method" ->');
        expect(routeStart, greaterThanOrEqualTo(0), reason: method);
        final nextRoute = RegExp(r'\\n\\s{20}"[A-Za-z]').firstMatch(
          native,
          routeStart + 1,
        );
        final routeEnd = nextRoute?.start ?? native.length;
        final route = native.substring(routeStart, routeEnd);
        expect(
          route,
          contains('runAiTask(result, requiresAiAccess = true)'),
          reason: '$method must require Native AI access before model work.',
        );
      }
      expect(
        native,
        contains('if (requiresAiAccess) aiModelAccessGate.requireAccess()'),
        reason: 'runAiTask must enforce the single process AI access gate.',
      );

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
