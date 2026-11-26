import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('产品定位不要求临床红旗 detector 或医学审批', () {
    final positioning = File(
      'docs/product-positioning-and-boundaries.md',
    ).readAsStringSync();

    expect(positioning, contains('不建设临床红旗 detector'));
    expect(positioning, contains('不要求医学背景人员'));
    expect(positioning, contains('不充当模型调用门禁'));
  });

  test('生产模型调用不依赖临床门禁字段或 Native detector', () {
    final productionFiles = <String, String>{
      'Flutter screen': File(
        'lib/screens/local_ai_interview_screen.dart',
      ).readAsStringSync(),
      'Local AI service': File(
        'lib/services/local_ai_service.dart',
      ).readAsStringSync(),
      'Assistant orchestrator': File(
        'lib/services/assistant_conversation_orchestrator.dart',
      ).readAsStringSync(),
      'Android MainActivity': File(
        'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
      ).readAsStringSync(),
    };

    for (final entry in productionFiles.entries) {
      for (final retiredContract in [
        'RedFlagGate',
        'RedFlagPreflight',
        'NativeRedFlagExecutionBoundary',
        'runAiTaskAfterNativeRedFlag',
        'requireMedicalSafety',
        'require_red_flag',
        'red_flag_context',
      ]) {
        expect(
          entry.value,
          isNot(contains(retiredContract)),
          reason: '${entry.key} must not depend on ${retiredContract}',
        );
      }
    }
  });

  test('通用 Native AI 访问授权和一般性求助提醒仍保留', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
    ).readAsStringSync();
    final gate = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiModelAccessGate.kt',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/local_ai_interview_screen.dart',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains('if (requiresAiAccess) aiModelAccessGate.requireAccess()'),
    );
    expect(gate, contains('AiModelAccessGate'));
    expect(screen, contains('紧迫危险中'));
    expect(screen, isNot(contains('胸痛、明显呼吸困难')));
    expect(mainActivity, contains('联系当地急救服务'));
    expect(mainActivity, isNot(contains('胸痛、明显呼吸困难')));
  });
}
