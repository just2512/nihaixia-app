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
    for (var index = 0; index < branches.length; index++) {
      final match = branches[index];
      final name = match.group(1)!;
      final end = index + 1 < branches.length
          ? branches[index + 1].start
          : handler.length;
      final body = handler.substring(match.start, end);
      if (maintenanceOnly.contains(name)) continue;
      expect(
        body.contains('requiresAiAccess = true') ||
            body.contains('runAiTaskAfterNativeRedFlag'),
        isTrue,
        reason: 'Native AI handler "$name" must require ai_access',
      );
    }

    const internalModelPaths = {
      'loadLocalModel',
      'sendWithFirstTurnGpuFallback',
      'recreateCpuEngineForRecovery',
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
