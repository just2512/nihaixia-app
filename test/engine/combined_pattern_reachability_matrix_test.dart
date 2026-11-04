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

  final cases = <({String key, String meridian, Map<String, dynamic> answers, String? pulse, String? secondary})>[
    (key: CombinedPatternCondition.sunYangmingBase, meridian: '太阳', answers: {'constipated': true, 'diarrhea': true, 'history_mistreatment': false}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangBase, meridian: '太阳', answers: {'bitter_mouth': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.shaoyangYangmingBase, meridian: '少阳', answers: {'constipated': true, 'diarrhea': true, 'food_stagnation': true}, pulse: '滑', secondary: '数'),
    (key: CombinedPatternCondition.taiyinShaoyinBase, meridian: '太阴', answers: {'drowsy': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingVomit, meridian: '太阳', answers: {'constipated': true, 'nausea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingChestFull, meridian: '太阳', answers: {'constipated': true, 'breathing': '喘'}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangDiarrhea, meridian: '太阳', answers: {'bitter_mouth': true, 'diarrhea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyangVomit, meridian: '太阳', answers: {'bitter_mouth': true, 'nausea': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.jueyinShaoyang, meridian: '厥阴', answers: {'bitter_mouth': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunYangmingUnresolved, meridian: '太阳', answers: {'constipated': true, 'has_sweat': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.threeYangSleep, meridian: '太阳', answers: {'thirsty': true, 'bitter_mouth': true, 'drowsy': true, 'has_sweat': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.sunShaoyinTwoCold, meridian: '太阳', answers: {'drowsy': true}, pulse: null, secondary: null),
    (key: CombinedPatternCondition.shaoyangTaiyin, meridian: '少阳', answers: {'diarrhea': true, 'abdominal_pain': true}, pulse: null, secondary: null),
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
      answers: {
        ...item.answers,
        'headache': true,
        'palpitation': true,
      },
      tenQuestionIndex: 0,
      qAnswers: structured
          ? const {kQ1: 1, kQ4: 2, kQ2: 12, kQ3: 1, kQ5: 1, kQ10: 2}
          : const {},
      pulseType: item.pulse,
      pulseTypeSecondary: item.secondary,
    );
  }

  group('合病规则可达性矩阵', () {
    for (final item in cases) {
      test('${item.key}：结构化主路径最终采用规则表方剂', () {
        final engine = DiagnosticEngine()
          ..restoreSnapshot(snapshotFor(item, structured: true));
        final result = engine.diagnose();
        final expected = DiagnosticRules.combinedPatterns
            .singleWhere((pattern) => pattern.condition == item.key);
        expect(engine.combinedPatternCondition, item.key);
        expect(result, isNotNull);
        expect(result!.formula, expected.formula);
        expect(result.recommendedFormulas, [expected.formula]);
      });

      test('${item.key}：旧兜底路径最终采用规则表方剂', () {
        final engine = DiagnosticEngine()
          ..restoreSnapshot(snapshotFor(item, structured: false));
        final result = engine.diagnose();
        final expected = DiagnosticRules.combinedPatterns
            .singleWhere((pattern) => pattern.condition == item.key);
        expect(engine.combinedPatternCondition, item.key);
        expect(result, isNotNull);
        expect(result!.formula, expected.formula);
        expect(result.recommendedFormulas, [expected.formula]);
        expect(result.prescription?.formulaName, expected.formula);
      });
    }

    test('规则表中没有生产赋值点的三阳基础条件保持明确不可达', () {
      final keys = cases.map((item) => item.key).toSet();
      expect(keys, hasLength(14));
      expect(
        DiagnosticRules.combinedPatterns.map((pattern) => pattern.condition),
        contains(CombinedPatternCondition.threeYangBase),
      );
      expect(keys, isNot(contains(CombinedPatternCondition.threeYangBase)));
    });

    test('规则表中每个条件键唯一，且所有可达键均有对应条目', () {
      final tableKeys =
          DiagnosticRules.combinedPatterns.map((pattern) => pattern.condition).toList();
      expect(tableKeys.toSet(), hasLength(tableKeys.length));
      expect(tableKeys.toSet(), containsAll(cases.map((item) => item.key)));
    });
  });
}
