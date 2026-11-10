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
    test('舌苔和舌形只接受 canonical 选项或明确注释', () {
      expect(DiagnosticRules.canonicalTongueCoating('薄白'), '薄白');
      expect(DiagnosticRules.canonicalTongueCoating('黄厚（燥苔）'), '黄厚');
      expect(DiagnosticRules.canonicalTongueCoating('黄厚偏白'), isNull);
      expect(DiagnosticRules.canonicalTongueCoating('不清楚'), isNull);
      expect(DiagnosticRules.canonicalTongueShape('绛紫'), '绛紫');
      expect(DiagnosticRules.canonicalTongueShape('淡白(气血不足)'), '淡白');
      expect(DiagnosticRules.canonicalTongueShape('暗红'), isNull);
    });

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

    test('没有主脉或主兼脉重复时不保留无效兼脉', () {
      final engine = DiagnosticEngine();
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '浮',
        pulseTypeSecondary: '浮',
      );
      expect(engine.createSnapshot().pulseType, '浮');
      expect(engine.createSnapshot().pulseTypeSecondary, isNull);
      expect(engine.createSnapshot().answers.containsKey('pulse_type_secondary'), isFalse);

      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '浮数',
        pulseTypeSecondary: '紧',
      );
      expect(engine.createSnapshot().pulseType, isNull);
      expect(engine.createSnapshot().pulseTypeSecondary, isNull);
      expect(engine.createSnapshot().answers.containsKey('pulse_type'), isFalse);
      expect(engine.createSnapshot().answers.containsKey('pulse_type_secondary'), isFalse);
    });

    test('恢复旧快照时重新规范化舌苔舌形并清除无效值', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'tongue_coating': '黄厚偏白',
          'tongue_shape': '淡白',
          'tongue_red_coated_yellow': true,
          'tongue_purple': true,
          'tongue_swollen': true,
        },
        tenQuestionIndex: 0,
        tongueCoating: '黄厚偏白',
        tongueShape: '淡白',
      ));
      final snapshot = engine.createSnapshot();
      expect(snapshot.tongueCoating, isNull);
      expect(snapshot.tongueShape, '淡白');
      expect(snapshot.answers.containsKey('tongue_coating'), isFalse);
      expect(snapshot.answers['tongue_shape'], '淡白');
      expect(snapshot.answers['tongue_red_coated_yellow'], isNull);
      expect(snapshot.answers['tongue_pale_coated_white'], isTrue);
      expect(snapshot.answers.containsKey('tongue_purple'), isFalse);
      expect(snapshot.answers.containsKey('tongue_swollen'), isFalse);
    });

    test('恢复旧快照时重新规范化脉值并清除无效兼脉', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'pulse_type': '浮数',
          'pulse_type_secondary': '浮',
        },
        tenQuestionIndex: 0,
        pulseType: '浮数',
        pulseTypeSecondary: '浮',
      ));
      final snapshot = engine.createSnapshot();
      expect(snapshot.pulseType, isNull);
      expect(snapshot.pulseTypeSecondary, isNull);
      expect(snapshot.answers.containsKey('pulse_type'), isFalse);
      expect(snapshot.answers.containsKey('pulse_type_secondary'), isFalse);
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
    test('只有兼脉与舌象冲突时也必须触发交叉核验', () {
      final engine = DiagnosticEngine();
      engine.answerTemperaturePattern('fever_chills');
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '浮',
        pulseTypeSecondary: '数',
      );

      final questions = engine.getPulseTongueFollowUpQuestions();
      expect(
        questions.map((question) => question.key),
        containsAll(['pulse_cross_drink', 'pulse_cross_urine', 'pulse_cross_limbs']),
      );
    });

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

    test('不确定追问不会删除其他问项已经取得的阳性证据', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阴',
        answers: const {
          'diarrhea': true,
          'abdomen_pain_relief': true,
          'no_thirst': true,
        },
        tenQuestionIndex: 0,
        tongueCoating: '白厚',
        tongueShape: '淡白',
        pulseType: '弦',
      ));

      engine.answerFollowUp('pulse_cross_taiyin', '不确定');
      final answers = engine.createSnapshot().answers;
      expect(answers['diarrhea'], isTrue);
      expect(answers['abdomen_pain_relief'], isTrue);
      expect(answers['no_thirst'], isTrue);
      expect(answers['pulse_cross_taiyin_answered'], isTrue);
    });

    test('不确定答案保留为缺失证据，不写入阴性标志且不重复追问', () {
      final cases = <String, List<String>>{
        'pulse_cross_drink': [
          'no_thirst', 'thirsty', 'hot_drink', 'cold_drink',
          'thirst_strong', 'thirst_no_drink',
        ],
        'pulse_cross_urine': ['urine_clear', 'urine_short', 'urine_difficult'],
        'pulse_cross_limbs': ['cold_limbs', 'warm_limbs'],
        'pulse_cross_surface': ['chills', 'headache', 'neck_stiff', 'no_chills'],
        'pulse_cross_interior': [
          'constipated', 'diarrhea', 'abdomen_pain_relief', 'abdomen_pain_press',
        ],
        'pulse_cross_shaoyang': [
          'bitter_mouth', 'dry_throat', 'alternating_chills',
        ],
        'pulse_cross_taiyin': [
          'diarrhea', 'abdomen_pain_relief', 'no_thirst', 'poor_appetite',
        ],
      };
      for (final entry in cases.entries) {
        final engine = DiagnosticEngine();
        engine.answerFollowUp(entry.key, '不确定');
        final answers = engine.createSnapshot().answers;
        expect(answers['${entry.key}_answered'], isTrue, reason: entry.key);
        for (final evidenceKey in entry.value) {
          expect(answers.containsKey(evidenceKey), isFalse,
              reason: '${entry.key} must not infer ${evidenceKey}');
        }
      }

      final engine = DiagnosticEngine();
      engine.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        pulseType: '数',
      );
      engine.answerFollowUp('pulse_cross_drink', '不确定');
      engine.answerFollowUp('pulse_cross_urine', '不清楚');
      engine.answerFollowUp('pulse_cross_limbs', '不清楚');
      final assessment = engine.createSnapshot();
      final pulseTongueAssessment = engine.getPulseTongueAssessment();
      expect(pulseTongueAssessment, isNotNull);
      expect(pulseTongueAssessment!.status, '待补充问诊');
      expect(pulseTongueAssessment.missingEvidence,
          containsAll(['饮水偏好', '小便情况', '四肢温度']));
      expect(engine.getPulseTongueFollowUpQuestions(), isEmpty);
      expect(assessment.answers['thirsty'], isNull);
      expect(assessment.answers['urine_clear'], isNull);
      expect(assessment.answers['cold_limbs'], isNull);
    });
  });
}
