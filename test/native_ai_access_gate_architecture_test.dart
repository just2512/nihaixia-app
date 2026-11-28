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
    // Enabling must ack synchronously. Queueing enable behind model work let a
    // Dart-side timeout observe unavailable while Native was about to open the
    // gate, splitting the two authorization states.
    expect(mainActivity, contains('result.success(mapOf("enabled" to true'));
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
    const legacyFailClosed = {
      'sendMessage': 'STRUCTURED_REASONING_PROTOCOL_REQUIRED',
      'sendImage': 'STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED',
      'sendAudio': 'STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED',
    };
    for (var index = 0; index < branches.length; index++) {
      final match = branches[index];
      final name = match.group(1)!;
      final end = index + 1 < branches.length
          ? branches[index + 1].start
          : handler.length;
      final body = handler.substring(match.start, end);
      if (maintenanceOnly.contains(name)) continue;
      final failureCode = legacyFailClosed[name];
      if (failureCode != null) {
        // Retired unstructured endpoints must fail closed before inference.
        // They do not call the model and therefore do not need the gate on
        // this branch; the only path that may reach LiteRT is gated below.
        expect(
          body,
          contains(failureCode),
          reason: 'Legacy Native endpoint "$name" must fail closed',
        );
        expect(
          body,
          isNot(contains('runAiTask(')),
          reason: 'Legacy Native endpoint "$name" must not call the model',
        );
        continue;
      }
      expect(
        body,
        contains('requiresAiAccess = true'),
        reason: 'Native AI handler "$name" must require ai_access',
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
