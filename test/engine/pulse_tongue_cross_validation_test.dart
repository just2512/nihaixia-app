import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
  });

  group('脉象 canonical 输入', () {
    test('复合脉先匹配最长值，不截断为单字脉', () {
      expect(DiagnosticRules.canonicalPulse('微弱'), '微弱');
      expect(DiagnosticRules.canonicalPulse('微弱（按之无力）'), '微弱');
      expect(DiagnosticRules.canonicalPulse('沉紧'), '沉紧');
      expect(DiagnosticRules.canonicalPulse('沉紧（里寒）'), '沉紧');
      expect(DiagnosticRules.canonicalPulse('洪'), '洪');
      expect(DiagnosticRules.canonicalPulse('不清楚'), isNull);
      expect(DiagnosticRules.canonicalPulse('浮数'), isNull);
      expect(DiagnosticRules.canonicalPulse('浮紧'), isNull);
    });
  });

  group('单脉与组合脉区分', () {
    test('只录入主脉时不误报组合脉', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {},
        tenQuestionIndex: 0,
        qAnswers: const {
          kQ1: 1, kQ4: 2, kQ2: 12, kQ3: 1, kQ5: 1, kQ10: 2,
        },
        pulseType: '浮',
      ));
      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.pulseCombination, isNull);
      expect(result.pulseType, '浮');
      expect(result.pulseTypeSecondary, isNull);
    });

    test('主脉+兼脉同时匹配时才返回组合脉', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {},
        tenQuestionIndex: 0,
        qAnswers: const {
          kQ1: 1, kQ4: 2, kQ2: 12, kQ3: 1, kQ5: 1, kQ10: 2,
        },
        pulseType: '浮',
        pulseTypeSecondary: '紧',
      ));
      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.pulseCombination, isNotNull);
      expect(result.pulseCombination!.pulse1, '浮');
      expect(result.pulseCombination!.pulse2, '紧');
      expect(result.pulseType, '浮');
      expect(result.pulseTypeSecondary, '紧');
    });

    test('兼脉状态纳入快照', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {},
        tenQuestionIndex: 0,
        pulseType: '浮',
        pulseTypeSecondary: '紧',
      ));
      expect(engine.createSnapshot().pulseTypeSecondary, '紧');
    });
  });

  group('脉舌问诊交叉核验', () {
    test('脉舌冲突不再自动指定脉或舌优先，并要求补充问诊', () {
      final engine = DiagnosticEngine();
      engine.answerTemperaturePattern('fever_chills');
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '数',
      );
      final questions = engine.getPulseTongueFollowUpQuestions();
      expect(questions.map((q) => q.key),
          containsAll(['pulse_cross_drink', 'pulse_cross_urine', 'pulse_cross_limbs']));
    });

    test('补充问诊后交叉证据被保留', () {
      final engine = DiagnosticEngine();
      engine.answerTemperaturePattern('fever_chills');
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '数',
      );
      engine.answerFollowUp('pulse_cross_drink', '口渴，喜热饮');
      engine.answerFollowUp('pulse_cross_urine', '清长色淡');
      engine.answerFollowUp('pulse_cross_limbs', '偏冷');
      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.pulseTongueAssessment, isNotNull);
      expect(result.pulseTongueAssessment!.supportingEvidence,
          containsAll(['喜热饮', '小便清长', '四肢偏冷']));
      expect(result.pulseTongueContradiction, contains('不自动以脉或舌单方优先'));
    });

    test('迟脉红舌冲突的中性小便与冷热不均回答也会完成追问', () {
      final engine = DiagnosticEngine();
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '红',
        pulseType: '迟',
      );
      final initial = engine.getPulseTongueFollowUpQuestions();
      expect(initial.map((q) => q.key),
          containsAll(['pulse_cross_drink', 'pulse_cross_urine', 'pulse_cross_limbs']));

      engine.answerFollowUp('pulse_cross_urine', '正常');
      engine.answerFollowUp('pulse_cross_limbs', '冷热不均');
      final remaining = engine.getPulseTongueFollowUpQuestions();
      expect(remaining.map((q) => q.key),
          isNot(contains('pulse_cross_urine')));
      expect(remaining.map((q) => q.key),
          isNot(contains('pulse_cross_limbs')));
      expect(engine.createSnapshot().answers['pulse_cross_urine_answered'], isTrue);
      expect(engine.createSnapshot().answers['pulse_cross_limbs_answered'], isTrue);
    });

    test('弦脉白厚苔冲突的少阳与太阴问诊回答后不重复追问', () {
      final engine = DiagnosticEngine();
      engine.answerTonguePulse(
        tongueCoating: '白厚',
        tongueShape: '淡白',
        pulseType: '弦',
      );
      final initial = engine.getPulseTongueFollowUpQuestions();
      expect(initial.map((q) => q.key),
          containsAll(['pulse_cross_shaoyang', 'pulse_cross_taiyin']));

      engine.answerFollowUp('pulse_cross_shaoyang', '都没有');
      engine.answerFollowUp('pulse_cross_taiyin', '都没有');
      final remaining = engine.getPulseTongueFollowUpQuestions();
      expect(remaining.map((q) => q.key),
          isNot(contains('pulse_cross_shaoyang')));
      expect(remaining.map((q) => q.key),
          isNot(contains('pulse_cross_taiyin')));
    });

    test('正常或不确定的小便与冷热不均回答不会被重复追问', () {
      final engine = DiagnosticEngine();
      engine.answerTemperaturePattern('fever_chills');
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '数',
      );
      final initial = engine.getPulseTongueFollowUpQuestions();
      expect(initial.map((q) => q.key),
          containsAll(['pulse_cross_urine', 'pulse_cross_limbs']));

      engine.answerFollowUp('pulse_cross_urine', '正常');
      engine.answerFollowUp('pulse_cross_limbs', '冷热不均');
      final remaining = engine.getPulseTongueFollowUpQuestions();
      expect(remaining.map((q) => q.key),
          isNot(contains('pulse_cross_urine')));
      expect(remaining.map((q) => q.key),
          isNot(contains('pulse_cross_limbs')));
      expect(engine.createSnapshot().answers['urine_clear'], isFalse);
      expect(engine.createSnapshot().answers['cold_limbs'], isFalse);
    });
  });
}
