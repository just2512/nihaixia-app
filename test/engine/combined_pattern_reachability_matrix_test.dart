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

  final cases = <({
    String key,
    String meridian,
    Map<String, dynamic> answers,
    String? pulse,
    String? secondary,
  })>[
    (key: CombinedPatternCondition.sunYangmingBase, meridian: '太阳', answers: {'constipated': true, 'diarrhea': true, 'history_mistreatment': false}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangBase, meridian: '太阳', answers: {'temperature': 'fever_chills', 'joint_pain': true, 'clause146_mild_nausea': true, 'illness_duration_6_7': true, 'epigastric_fullness': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.shaoyangYangmingBase, meridian: '少阳', answers: {'constipated': true, 'diarrhea': true, 'food_stagnation': true}, pulse: '滑', secondary: '数'),
    (key: CombinedPatternCondition.taiyinShaoyinBase, meridian: '太阴', answers: {'drowsy': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingVomit, meridian: '太阳', answers: {'constipated': true, 'diarrhea': false, 'nausea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingChestFull, meridian: '太阳', answers: {'constipated': true, 'breathing': '喘'}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangDiarrhea, meridian: '太阳', answers: {'bitter_mouth': true, 'diarrhea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangVomit, meridian: '太阳', answers: {'bitter_mouth': true, 'nausea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.jueyinShaoyang, meridian: '厥阴', answers: {'bitter_mouth': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.threeYangSleep, meridian: '太阳', answers: {'thirsty': true, 'bitter_mouth': true, 'drowsy': true, 'has_sweat': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.shaoyangTaiyin, meridian: '少阳', answers: {'illness_duration_5_6': true, 'shaoyang147_prior_sweat_then_purge': true, 'chest_minor_knot': true, 'urine_difficult': true, 'thirsty': true, 'nausea': false, 'vomiting': false, 'head_sweat': true, 'alternating_chills': true, 'irritable': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunTaiyin, meridian: '太阳', answers: {'temperature': 'fever_chills', 'fever': true, 'has_sweat': false, 'diarrhea': true, 'history_mistreatment': true, 'sun_taiyin_repeated_purgation': true, 'epigastric_hard': true}, pulse: null, secondary: null),
  ];

  EngineSnapshot snapshotFor(
    ({String key, String meridian, Map<String, dynamic> answers, String? pulse, String? secondary}) item, {
    required bool structured,
  }) {
    return EngineSnapshot(
      stage: DiagnosticStage.meridianLocation,
      selectedSymptoms: const [],
      meridianDirection: item.meridian,
      answers: {...item.answers, 'headache': true, 'palpitation': true},
      tenQuestionIndex: 0,
      qAnswers: structured ? const {kQ1: 1, kQ4: 2, kQ2: 12, kQ3: 1, kQ5: 1, kQ10: 2} : const {},
      pulseType: item.pulse,
      pulseTypeSecondary: item.secondary,
    );
  }

  group('合病规则可达性矩阵', () {
    for (final item in cases) {
      test('${item.key}：结构化主路径最终采用对应规则表结果', () {
        final engine = DiagnosticEngine()..restoreSnapshot(snapshotFor(item, structured: true));
        expect(engine.diagnoseByRules().formula, isNotEmpty, reason: '确认结构化规则命中');
        final result = engine.diagnose();
        final expected = DiagnosticRules.combinedPatterns.singleWhere((p) => p.condition == item.key);
        expect(engine.combinedPatternCondition, item.key);
        expect(result, isNotNull);
        final diagnosis = result!;
        expect(diagnosis.pattern, expected.description);
        expect(diagnosis.formula, expected.formula);
        if (expected.formula.isEmpty) {
          expect(diagnosis.recommendedFormulas, isEmpty);
          expect(diagnosis.prescription, isNull);
          expect(diagnosis.recommendConsult, isTrue);
        } else {
          expect(diagnosis.recommendedFormulas, [expected.formula]);
          expect(diagnosis.prescription?.formulaName, expected.formula);
        }
        expect(diagnosis.combinedMeridian, expected.isExplicitCombined ? isNotNull : isNull);
      });

      test('${item.key}：旧兜底路径最终采用对应规则表结果', () {
        final engine = DiagnosticEngine()..restoreSnapshot(snapshotFor(item, structured: false));
        expect(engine.diagnoseByRules().formula, isEmpty, reason: '确认结构化规则未命中');
        final result = engine.diagnose();
        final expected = DiagnosticRules.combinedPatterns.singleWhere((p) => p.condition == item.key);
        expect(engine.combinedPatternCondition, item.key);
        expect(result, isNotNull);
        final diagnosis = result!;
        expect(diagnosis.pattern, expected.description);
        expect(diagnosis.formula, expected.formula);
        if (expected.formula.isEmpty) {
          expect(diagnosis.recommendedFormulas, isEmpty);
          expect(diagnosis.prescription, isNull);
          expect(diagnosis.recommendConsult, isTrue);
        } else {
          expect(diagnosis.recommendedFormulas, [expected.formula]);
          expect(diagnosis.prescription?.formulaName, expected.formula);
        }
        expect(diagnosis.combinedMeridian, expected.isExplicitCombined ? isNotNull : isNull);
      });
    }

    test('第32条必须明确排除误下史；未知或有误下史均不得命中', () {
      for (final history in <bool?>[null, true]) {
        final answers = <String, dynamic>{
          'constipated': true,
          'diarrhea': true,
          'headache': true,
          if (history != null) 'history_mistreatment': history,
        };
        final engine = DiagnosticEngine()
          ..restoreSnapshot(EngineSnapshot(
            stage: DiagnosticStage.meridianLocation,
            selectedSymptoms: const [],
            meridianDirection: '太阳',
            answers: answers,
            tenQuestionIndex: 0,
          ));

        engine.diagnose();

        expect(
          engine.combinedPatternCondition,
          isNot(CombinedPatternCondition.sunYangmingBase),
          reason: 'history_mistreatment=$history must fail closed',
        );
      }
    });

    test('第33条必须明确回答无下利；未知不能被当作阴性', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'constipated': true,
            'nausea': true,
            'headache': true,
          },
          tenQuestionIndex: 0,
        ));

      final prompts = engine.getRequiredCombinedPatternFollowUpQuestions();
      expect(prompts, hasLength(1));
      expect(prompts.single.key, 'combined_diarrhea_status');
      engine.diagnose();
      expect(
        engine.combinedPatternCondition,
        isNot(CombinedPatternCondition.sunYangmingVomit),
      );

      engine.answerFollowUp(
        'combined_diarrhea_status',
        '明确没有下利（第33条）',
      );
      final diagnosis = engine.diagnose();
      expect(
        engine.combinedPatternCondition,
        CombinedPatternCondition.sunYangmingVomit,
      );
      expect(diagnosis?.formula, '葛根加半夏汤');
      expect(diagnosis?.recommendedFormulas, ['葛根加半夏汤']);
    });

    test('第32条仅在明确无误下史时命中', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'constipated': true,
            'diarrhea': true,
            'history_mistreatment': false,
          },
          tenQuestionIndex: 0,
        ));

      final diagnosis = engine.diagnose();

      expect(engine.combinedPatternCondition, CombinedPatternCondition.sunYangmingBase);
      expect(diagnosis?.formula, '葛根汤');
      expect(diagnosis?.recommendedFormulas, ['葛根汤']);
    });

    test('第146条具体证据优先于宽泛太阳阳明组合，避免分支遮蔽', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'temperature': 'fever_chills',
            'joint_pain': true,
            'clause146_mild_nausea': true,
            'illness_duration_6_7': true,
            'epigastric_fullness': true,
            'constipated': true,
            'diarrhea': true,
            'history_mistreatment': false,
          },
          tenQuestionIndex: 0,
        ));
      engine.diagnose();
      expect(engine.combinedPatternCondition, CombinedPatternCondition.sunShaoyangBase);
    });

    test('第147条完整条文证据优先于少阳宽泛兼夹候选', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '少阳',
          answers: const {
            'illness_duration_5_6': true,
            'shaoyang147_prior_sweat_then_purge': true,
            'chest_minor_knot': true,
            'urine_difficult': true,
            'thirsty': true,
            'nausea': false,
            'vomiting': false,
            'head_sweat': true,
            'alternating_chills': true,
            'irritable': true,
            'constipated': true,
            'diarrhea': true,
            'food_stagnation': true,
          },
          pulseType: '滑',
          pulseTypeSecondary: '数',
          tenQuestionIndex: 0,
        ));
      engine.diagnose();
      expect(engine.combinedPatternCondition, CombinedPatternCondition.shaoyangTaiyin);
    });

    test('第163条完整条文证据优先于太阳阳明一般候选', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'temperature': 'fever_chills',
            'diarrhea': true,
            'history_mistreatment': true,
            'sun_taiyin_repeated_purgation': true,
            'epigastric_hard': true,
            'constipated': true,
          },
          tenQuestionIndex: 0,
        ));
      engine.diagnose();
      expect(engine.combinedPatternCondition, CombinedPatternCondition.sunTaiyin);
    });

    test('规则表唯一且只保留12条已审计关联', () {
      final keys = DiagnosticRules.combinedPatterns.map((p) => p.condition).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys, hasLength(12));
      expect(keys, isNot(contains(CombinedPatternCondition.threeYangBase)));
      expect(keys, isNot(contains(CombinedPatternCondition.sunYangmingUnresolved)));
      expect(keys, isNot(contains(CombinedPatternCondition.sunShaoyinTwoCold)));
    });

    test('合病条件键统一使用稳定 canonical ID', () {
      for (final pattern in DiagnosticRules.combinedPatterns) {
        expect(pattern.condition, startsWith('combined.'));
      }
      for (final entry in CombinedPatternCondition.legacyAliases.entries) {
        expect(
          CombinedPatternCondition.canonicalize(entry.key),
          entry.value,
          reason: 'legacy key: ${entry.key}',
        );
      }
    });

    test('恢复旧快照时将历史合病键规范化', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {},
          tenQuestionIndex: 0,
          combinedPatternCondition: 'sun_symptoms + yangming_symptoms',
        ));
      expect(
        engine.combinedPatternCondition,
        CombinedPatternCondition.sunYangmingBase,
      );
      expect(engine.suppressReferenceFormulaSuggestions, isFalse);
    });

    test('原文未载方剂或来源待核的项目关闭相似度方剂兜底', () {
      for (final key in [
        CombinedPatternCondition.taiyinShaoyinBase,
        CombinedPatternCondition.jueyinShaoyang,
        CombinedPatternCondition.threeYangSleep,
      ]) {
        final pattern = DiagnosticRules.combinedPatterns.singleWhere((p) => p.condition == key);
        expect(pattern.formula, isEmpty, reason: key);
        final engine = DiagnosticEngine()
          ..restoreSnapshot(EngineSnapshot(
            stage: DiagnosticStage.meridianLocation,
            selectedSymptoms: const [],
            meridianDirection: pattern.meridians.first,
            answers: const {},
            tenQuestionIndex: 0,
            combinedPatternCondition: key,
          ));
        expect(engine.suppressReferenceFormulaSuggestions, isTrue, reason: key);
      }
    });

    test('有原文方剂依据的合病规则不误关闭一般参考提示', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {},
          tenQuestionIndex: 0,
          combinedPatternCondition: CombinedPatternCondition.sunYangmingBase,
        ));
      expect(engine.suppressReferenceFormulaSuggestions, isFalse);
    });
  });
}
