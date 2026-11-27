import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Native LiteRT handler is behind the unified Native gate', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
    ).readAsStringSync();
    final gateSource = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiModelAccessGate.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('if (requiresAiAccess) aiModelAccessGate.requireAccess()'));
    expect(mainActivity, contains('if (!enabled) aiModelAccessGate.disable()'));
    expect(gateSource, contains('AiModelAccessGate(initiallyEnabled: Boolean = false)'));
    expect(gateSource, contains('currentEpoch()'));
    expect(gateSource, contains('expectedEpoch != epoch'));
    expect(gateSource, contains('@Volatile'));
    expect(gateSource, isNot(contains('SharedPreferences')));
    expect(gateSource, isNot(contains('File(')));

    final whenStart = mainActivity.indexOf('when (call.method)');
    final whenEnd = mainActivity.indexOf('else -> result.notImplemented()', whenStart);
    expect(whenStart, greaterThanOrEqualTo(0));
    expect(whenEnd, greaterThan(whenStart));
    final handler = mainActivity.substring(whenStart, whenEnd);
    final branchPattern = RegExp(r'^ {20}"([^"]+)"\s*->', multiLine: true);
    final branches = branchPattern.allMatches(handler).toList();
    expect(branches, isNotEmpty);

    const maintenanceOnly = {
      'setAiModelAccess',
      'getModelStatus',
      'setBackendPreference',
      'importModel',
      'releaseModel',
      'clearRuntimeCache',
    };
    const legacyClosedErrors = {
      'sendImage': 'STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED',
      'sendAudio': 'STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED',
      'sendMessage': 'STRUCTURED_REASONING_PROTOCOL_REQUIRED',
    };
    for (var index = 0; index < branches.length; index++) {
      final match = branches[index];
      final name = match.group(1)!;
      final end = index + 1 < branches.length
          ? branches[index + 1].start
          : handler.length;
      final body = handler.substring(match.start, end);
      if (maintenanceOnly.contains(name)) continue;
      final legacyError = legacyClosedErrors[name];
      if (legacyError != null) {
        // Compatibility endpoints are rejected before model inference. The
        // unified AI access gate is required for every active model handler;
        // a fail-closed legacy handler has no model access to authorize.
        expect(
          body,
          contains(legacyError),
          reason: 'Legacy Native handler "$name" must fail closed',
        );
        expect(
          body,
          isNot(contains('runAiTask(')),
          reason: 'Legacy Native handler "$name" must not call the model',
        );
        continue;
      }
      expect(
        body,
        contains('requiresAiAccess = true'),
        reason: 'Active Native AI handler "$name" must require ai_access',
      );
    }

    const internalModelPaths = {
      'loadLocalModel',
      'sendWithFirstTurnGpuFallback',
      'recreateCpuEngineForRecovery',
      'createConversationWithHistory',
      'resolveAssistantIntent',
      'extractBaziSlots',
      'understandTcmInterviewAnswer',
      'extractSymptoms',
      'restoreLocalConversation',
      'resetLocalConversation',
    };
    for (final methodName in internalModelPaths) {
      final start = mainActivity.indexOf('private fun $methodName(');
      expect(start, greaterThanOrEqualTo(0), reason: 'missing $methodName');
      final nextMethod = mainActivity.indexOf('\n    private fun ', start + 1);
      final body = mainActivity.substring(
        start,
        nextMethod < 0 ? mainActivity.length : nextMethod,
      );
      expect(
        body,
        contains('aiModelAccessGate.requireAccess()'),
        reason: '$methodName must defend its own Native model access path',
      );
    }
  });
}
