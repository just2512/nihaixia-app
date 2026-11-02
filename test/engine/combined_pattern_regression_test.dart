import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/data/formula_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
  });

  group('合病条件键', () {
    test('所有合病表项均使用集中定义的稳定键且不重复', () {
      final conditions =
          DiagnosticRules.combinedPatterns.map((p) => p.condition).toList();
      expect(conditions.toSet().length, conditions.length);
      expect(conditions, containsAll(<String>[
        CombinedPatternCondition.sunYangmingBase,
        CombinedPatternCondition.sunShaoyangBase,
        CombinedPatternCondition.shaoyangYangmingBase,
        CombinedPatternCondition.threeYangBase,
        CombinedPatternCondition.taiyinShaoyinBase,
        CombinedPatternCondition.sunYangmingVomit,
        CombinedPatternCondition.sunYangmingChestFull,
        CombinedPatternCondition.sunShaoyangDiarrhea,
        CombinedPatternCondition.sunShaoyangVomit,
        CombinedPatternCondition.shaoyangYangmingTidalFever,
        CombinedPatternCondition.yangmingShaoyinUrgent,
        CombinedPatternCondition.jueyinShaoyang,
        CombinedPatternCondition.sunYangmingUnresolved,
        CombinedPatternCondition.threeYangSleep,
        CombinedPatternCondition.sunYangmingInteriorHeat,
        CombinedPatternCondition.sunShaoyinTwoCold,
        CombinedPatternCondition.shaoyangTaiyin,
        CombinedPatternCondition.sunTaiyin,
        CombinedPatternCondition.sunYangmingDiarrheaHeat,
      ]));
    });
  });

  group('合病快照状态', () {
    test('restoreSnapshot 恢复合病条件键，createSnapshot 再次保存', () {
      final engine = DiagnosticEngine();
      final snapshot = EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        combinedMeridian: '少阳',
        combinedPatternCondition: CombinedPatternCondition.sunShaoyangBase,
        answers: const {},
        tenQuestionIndex: 0,
      );

      engine.restoreSnapshot(snapshot);
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangBase);

      final restored = engine.createSnapshot();
      expect(restored.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangBase);
    });
  });

  group('合病应用到结构化主路径', () {
    test('RuleEngine 命中时精确合病表覆盖主方并同步推荐方和合病经', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': true,
          'bitter_mouth': true,
          'dry_throat': true,
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
      ));

      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.formula, '柴胡桂枝汤');
      expect(result.recommendedFormulas, ['柴胡桂枝汤']);
      expect(result.combinedMeridian, '少阳');
      expect(result.pattern, contains('太阳少阳合病'));
      expect(result.prescription?.formulaName, '柴胡桂枝汤');
    });
  });

  group('合病结果优先级', () {
    test('旧六经补虚方优先逻辑不得覆盖已命中的精确合病表方', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': true,
          'bitter_mouth': true,
          'dry_throat': true,
          'palpitation': true,
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
        pulseType: '结',
      ));

      final result = engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangBase);
      expect(result, isNotNull);
      expect(result!.formula, '柴胡桂枝汤');
      expect(result.recommendedFormulas, ['柴胡桂枝汤']);
      expect(result.combinedMeridian, '少阳');
      expect(result.prescription?.formulaName, '柴胡桂枝汤');
    });
  });

  group('分支优先级', () {
    test('太阳阳明下利热分支优先于一般太阳阳明子型', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': false,
          'cold_limbs': false,
          'thirsty': true,
          'thirst_strong': true,
          'hot_palms_soles': true,
          'headache': true,
          'irritable': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
      ));

      // 无扁平规则答案时进入旧六经路径；无论旧路径是否有足够结果，
      // 合病条件必须由新分支确定为下利热，而不能被一般太阳阳明分支截获。
      final result = engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunYangmingDiarrheaHeat);
      expect(result, isNotNull);
      expect(result!.formula, '葛根黄芩黄连汤');
      expect(result.recommendedFormulas, ['葛根黄芩黄连汤']);
      expect(result.combinedMeridian, '阳明');
      expect(result.prescription?.formulaName, '葛根黄芩黄连汤');
    });

    test('三阳并病的目合则汗条件先于两经子型分支', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': true,
          'cold_limbs': false,
          'thirsty': true,
          'constipated': true,
          'bitter_mouth': true,
          'drowsy': true,
        },
        tenQuestionIndex: 0,
      ));

      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.threeYangSleep);
    });
  });

  group('合病检测器可达性矩阵', () {
    final cases = <({String name, String primary, Map<String, dynamic> answers, String expected})>[
      (name: '太阳少阳基础型', primary: '太阳', answers: {'bitter_mouth': true}, expected: CombinedPatternCondition.sunShaoyangBase),
      (name: '太阴少阴基础型', primary: '太阴', answers: {'drowsy': true}, expected: CombinedPatternCondition.taiyinShaoyinBase),
      (name: '太阳阳明呕吐型', primary: '太阳', answers: {'constipated': true, 'vomiting': true}, expected: CombinedPatternCondition.sunYangmingVomit),
      (name: '太阳阳明胸满型', primary: '太阳', answers: {'constipated': true, 'chest_fullness': true}, expected: CombinedPatternCondition.sunYangmingChestFull),
      (name: '太阳少阳下利型', primary: '太阳', answers: {'bitter_mouth': true, 'diarrhea': true}, expected: CombinedPatternCondition.sunShaoyangDiarrhea),
      (name: '太阳少阳呕吐型', primary: '太阳', answers: {'bitter_mouth': true, 'vomiting': true}, expected: CombinedPatternCondition.sunShaoyangVomit),
      (name: '少阳阳明潮热型', primary: '少阳', answers: {'constipated': true, 'tidal_fever': true}, expected: CombinedPatternCondition.shaoyangYangmingTidalFever),
      (name: '阳明少阴急下型', primary: '阳明', answers: {'drowsy': true}, expected: CombinedPatternCondition.yangmingShaoyinUrgent),
      (name: '厥阴少阳型', primary: '厥阴', answers: {'bitter_mouth': true}, expected: CombinedPatternCondition.jueyinShaoyang),
      (name: '太阳阳明未解型', primary: '太阳', answers: {'thirsty': true, 'hot_palms_soles': true, 'has_sweat': true}, expected: CombinedPatternCondition.sunYangmingUnresolved),
      (name: '三阳但欲寐型', primary: '太阳', answers: {'thirsty': true, 'bitter_mouth': true, 'drowsy': true, 'has_sweat': true}, expected: CombinedPatternCondition.threeYangSleep),
      (name: '太阳阳明里热型', primary: '太阳', answers: {'constipated': true, 'irritable': true, 'has_sweat': false}, expected: CombinedPatternCondition.sunYangmingInteriorHeat),
      (name: '太阳少阴两感型', primary: '太阳', answers: {'drowsy': true}, expected: CombinedPatternCondition.sunShaoyinTwoCold),
      (name: '少阳太阴型', primary: '少阳', answers: {'diarrhea': true, 'abdominal_pain': true}, expected: CombinedPatternCondition.shaoyangTaiyin),
      (name: '太阳太阴并病型', primary: '太阴', answers: {'temperature': 'fever_chills', 'diarrhea': true}, expected: CombinedPatternCondition.sunTaiyin),
      (name: '太阳阳明下利热型', primary: '太阳', answers: {'constipated': true, 'diarrhea': true}, expected: CombinedPatternCondition.sunYangmingDiarrheaHeat),
    ];

    for (final scenario in cases) {
      test('${scenario.name} 能生成精确条件键', () {
        final engine = DiagnosticEngine();
        engine.restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: scenario.primary,
          answers: scenario.answers,
          tenQuestionIndex: 0,
        ));

        engine.diagnose();
        expect(engine.combinedPatternCondition, scenario.expected);
      });
    }

    test('规则表中的三条基础键没有检测器赋值路径，不得被误报为可达', () {
      final unreachable = <String>{
        CombinedPatternCondition.sunYangmingBase,
        CombinedPatternCondition.shaoyangYangmingBase,
        CombinedPatternCondition.threeYangBase,
      };
      expect(cases.map((scenario) => scenario.expected).toSet().intersection(unreachable), isEmpty);
    });
  });

  group('合病条件遇到证据闸时安全拒绝', () {
    test('检测器产生合病条件但有效证据不足时，不输出合病方剂', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': false,
        },
        tenQuestionIndex: 0,
      ));

      final result = engine.diagnose();
      expect(engine.combinedPatternCondition, CombinedPatternCondition.sunShaoyangBase);
      expect(result, isNotNull);
      expect(result!.pattern, '辨证依据不足');
      expect(result.formula, isEmpty);
      expect(result.prescription, isNull);
      expect(result.combinedMeridian, isNull);
      expect(result.recommendConsult, isTrue);
    });
  });

}
