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
    (key: CombinedPatternCondition.sunShaoyangBase, meridian: '太阳', answers: {'temperature': 'fever_chills', 'joint_pain': true, 'nausea': true, 'epigastric_fullness': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.shaoyangYangmingBase, meridian: '少阳', answers: {'constipated': true, 'diarrhea': true, 'food_stagnation': true}, pulse: '滑', secondary: '数'),
    (key: CombinedPatternCondition.taiyinShaoyinBase, meridian: '太阴', answers: {'drowsy': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingVomit, meridian: '太阳', answers: {'constipated': true, 'nausea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingChestFull, meridian: '太阳', answers: {'constipated': true, 'breathing': '喘'}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangDiarrhea, meridian: '太阳', answers: {'bitter_mouth': true, 'diarrhea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangVomit, meridian: '太阳', answers: {'bitter_mouth': true, 'nausea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.jueyinShaoyang, meridian: '厥阴', answers: {'bitter_mouth': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.threeYangSleep, meridian: '太阳', answers: {'thirsty': true, 'bitter_mouth': true, 'drowsy': true, 'has_sweat': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.shaoyangTaiyin, meridian: '少阳', answers: {'shaoyang147_prior_sweat_then_purge': true, 'chest_minor_knot': true, 'urine_difficult': true, 'thirsty': true, 'nausea': false, 'head_sweat': true, 'alternating_chills': true, 'irritable': true}, pulse: null, secondary: null),
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

    test('规则表唯一且只保留12条已审计关联', () {
      final keys = DiagnosticRules.combinedPatterns.map((p) => p.condition).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys, hasLength(12));
      expect(keys, isNot(contains(CombinedPatternCondition.threeYangBase)));
      expect(keys, isNot(contains(CombinedPatternCondition.sunYangmingUnresolved)));
      expect(keys, isNot(contains(CombinedPatternCondition.sunShaoyinTwoCold)));
    });

    test('原文未载方剂或来源待核的项目不得自动出方', () {
      for (final key in [CombinedPatternCondition.taiyinShaoyinBase, CombinedPatternCondition.jueyinShaoyang, CombinedPatternCondition.threeYangSleep]) {
        final pattern = DiagnosticRules.combinedPatterns.singleWhere((p) => p.condition == key);
        expect(pattern.formula, isEmpty, reason: key);
      }
    });
  });
}
