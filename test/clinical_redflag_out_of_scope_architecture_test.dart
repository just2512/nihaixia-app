import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clinical red-flag checks do not gate consultation model context restore', () {
    final orchestrator = File(
      'lib/services/assistant_conversation_orchestrator.dart',
    ).readAsStringSync();
    final preflightStart =
        orchestrator.indexOf('static bool requiresMedicalSafetyPreflight(');
    expect(preflightStart, greaterThanOrEqualTo(0));
    final preflightEnd = orchestrator.indexOf(
      'static bool shouldExcludeFromIntentModel(',
      preflightStart,
    );
    expect(preflightEnd, greaterThan(preflightStart));
    final preflight = orchestrator.substring(preflightStart, preflightEnd);
    expect(preflight, contains('}) => false;'));

    final screen = File(
      'lib/screens/local_ai_interview_screen.dart',
    ).readAsStringSync();
    expect(screen, isNot(contains('requireMedicalSafety: true')));
    expect(screen, isNot(contains('requireAssessment: true')));
  });

  test('Native model access remains governed by the single ai_access gate', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
    ).readAsStringSync();
    final gateSource = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiModelAccessGate.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('if (requiresAiAccess) aiModelAccessGate.requireAccess()'));
    expect(mainActivity, contains('private fun runAiTaskAfterNativeRedFlag('));
    expect(mainActivity, contains('if (!required)'));
    expect(gateSource, contains('AiModelAccessGate(initiallyEnabled: Boolean = false)'));
    expect(gateSource, contains('requireAccess()'));
  });
}
