import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';

void main() {
  DiagnosticEngine engineFor({
    String? pulse = '浮',
    String? secondary = '大',
    Map<String, dynamic> extraAnswers = const {},
  }) {
    return DiagnosticEngine()
      ..restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: {
          'thirsty': true,
          'bitter_mouth': true,
          'drowsy': true,
          'has_sweat': true,
          'headache': true,
          'palpitation': true,
          ...extraAnswers,
        },
        tenQuestionIndex: 0,
        qAnswers: const {
          kQ1: 1,
          kQ4: 2,
          kQ2: 12,
          kQ3: 1,
          kQ5: 1,
          kQ10: 2,
        },
        pulseType: pulse,
        pulseTypeSecondary: secondary,
      ));
  }

  group('第268条三阳合病必须核验原文脉象', () {
    test('浮大组合出现后追问“上关上”是否经专业人员确认', () {
      final engine = engineFor();
      final prompts = engine.getRequiredCombinedPatternFollowUpQuestions();

      expect(prompts, hasLength(1));
      expect(prompts.single.key, 'three_yang_pulse_position');
      expect(prompts.single.question, contains('上关上'));
      expect(prompts.single.options, contains('已由专业人员确认'));
    });

    test('没有浮大组合时不得追问位置，也不得命中第268条', () {
      final engine = engineFor(pulse: '浮', secondary: null);
      expect(engine.getRequiredCombinedPatternFollowUpQuestions(), isEmpty);
      engine.diagnose();
      expect(
        engine.combinedPatternCondition,
        isNot(CombinedPatternCondition.threeYangSleep),
      );
    });

    test('未确认或不清楚上关上位置时不得命中第268条', () {
      for (final answer in ['未确认', '不清楚']) {
        final engine = engineFor();
        engine.answerFollowUp('three_yang_pulse_position', answer);
        engine.diagnose();
        expect(
          engine.combinedPatternCondition,
          isNot(CombinedPatternCondition.threeYangSleep),
          reason: 'answer=$answer',
        );
      }
    });

    test('仅在专业人员确认浮大上关上后才可命中第268条', () {
      final engine = engineFor();
      engine.answerFollowUp(
        'three_yang_pulse_position',
        '已由专业人员确认',
      );
      engine.diagnose();

      expect(
        engine.combinedPatternCondition,
        CombinedPatternCondition.threeYangSleep,
      );
    });
  });
}
