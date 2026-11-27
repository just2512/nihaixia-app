import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';

void main() {
  group('合病追问与最终检测共享同一少阳证据口径', () {
    DiagnosticEngine engineFor(Map<String, dynamic> answers) {
      return DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: {
            'headache': true,
            'vomiting': true,
            ...answers,
          },
          tenQuestionIndex: 0,
        ));
    }

    test('口苦、咽干、往来寒热任一达到阈值时，呕吐候选先追问第172条自下利', () {
      final cases = <Map<String, dynamic>>[
        {'bitter_mouth': true},
        {'dry_throat': true},
        {'temperature': 'alternating_chills_fever'},
      ];

      for (final answers in cases) {
        final engine = engineFor(answers);
        final prompts = engine.getRequiredCombinedPatternFollowUpQuestions();

        expect(prompts, hasLength(1), reason: '$answers should reach clause 172 gate');
        expect(prompts.single.key, 'combined_clause172_diarrhea');

        engine.answerFollowUp(
          'combined_clause172_diarrhea',
          '明确有自下利（第172条）',
        );
        final diagnosis = engine.diagnose();

        expect(
          engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangVomit,
          reason: '$answers should reach the same detector after confirmation',
        );
        expect(diagnosis?.formula, '黄芩加半夏生姜汤');
      }
    });

    test('仅恶心贡献少阳1分时，不得提前询问或命中第172条', () {
      final engine = engineFor({'nausea': true});

      expect(engine.getRequiredCombinedPatternFollowUpQuestions(), isEmpty);
      engine.diagnose();

      expect(
        engine.combinedPatternCondition,
        isNot(CombinedPatternCondition.sunShaoyangVomit),
      );
    });

    test('第172条回答明确无下利或不确定时均不得命中呕吐方', () {
      for (final answer in ['没有下利', '不确定']) {
        final engine = engineFor({'bitter_mouth': true});
        final prompts = engine.getRequiredCombinedPatternFollowUpQuestions();
        expect(prompts.single.key, 'combined_clause172_diarrhea');

        engine.answerFollowUp('combined_clause172_diarrhea', answer);
        engine.diagnose();

        expect(
          engine.combinedPatternCondition,
          isNot(CombinedPatternCondition.sunShaoyangVomit),
          reason: 'answer=$answer must fail closed',
        );
      }
    });
  });
}
