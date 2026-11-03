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
        CombinedPatternCondition.jueyinShaoyang,
        CombinedPatternCondition.sunYangmingUnresolved,
        CombinedPatternCondition.threeYangSleep,
        CombinedPatternCondition.sunShaoyinTwoCold,
        CombinedPatternCondition.shaoyangTaiyin,
        CombinedPatternCondition.sunTaiyin,
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
      expect(result.combinedMeridian, isNull);
      expect(result.pattern, contains('兼见少阳证'));
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
      // 第146条是太阳表证兼少阳证，不是原文明确的合病；不应输出合病经标签。
      expect(result.combinedMeridian, isNull);
      expect(result.prescription?.formulaName, '柴胡桂枝汤');
    });
  });

  group('合病条件与条文前提', () {
    test('太阳阳明下利且明确无误下史时命中第32条葛根汤', () {
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
          'hot_palms_soles': true,
          'diarrhea': true,
          'history_mistreatment': false,
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
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunYangmingBase);
      expect(result, isNotNull);
      expect(result!.formula, '葛根汤');
      expect(result.recommendedFormulas, ['葛根汤']);
      expect(result.combinedMeridian, '阳明');
      expect(result.prescription?.formulaName, '葛根汤');
    });

    test('误下史存在时不再误触发合病葛根汤或第34条葛根芩连汤', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': true,
          'thirsty': true,
          'hot_palms_soles': true,
          'diarrhea': true,
          'history_mistreatment': true,
          'asthma': true,
        },
        tenQuestionIndex: 0,
        pulseType: '促',
      ));

      final result = engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
      expect(result, isNotNull);
      expect(result!.combinedMeridian, isNull);
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

  group('非合病潮热路径', () {
    test('潮热不能单独命中第256条阳明少阳合病', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'constipated': true,
          'tidal_fever': true,
        },
        tenQuestionIndex: 0,
      ));

      final result = engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
      expect(result, isNotNull);
      expect(result!.combinedMeridian, isNull);
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
      (name: '厥阴少阳型', primary: '厥阴', answers: {'bitter_mouth': true}, expected: CombinedPatternCondition.jueyinShaoyang),
      (name: '太阳阳明未解型', primary: '太阳', answers: {'thirsty': true, 'hot_palms_soles': true, 'has_sweat': true}, expected: CombinedPatternCondition.sunYangmingUnresolved),
      (name: '三阳但欲寐型', primary: '太阳', answers: {'thirsty': true, 'bitter_mouth': true, 'drowsy': true, 'has_sweat': true}, expected: CombinedPatternCondition.threeYangSleep),
      (name: '太阳少阴两感型', primary: '太阳', answers: {'drowsy': true}, expected: CombinedPatternCondition.sunShaoyinTwoCold),
      (name: '少阳太阴型', primary: '少阳', answers: {'diarrhea': true, 'abdominal_pain': true}, expected: CombinedPatternCondition.shaoyangTaiyin),
      (name: '太阳太阴并病型', primary: '太阴', answers: {'temperature': 'fever_chills', 'diarrhea': true}, expected: CombinedPatternCondition.sunTaiyin),
      (name: '太阳阳明下利基础型', primary: '太阳', answers: {'constipated': true, 'diarrhea': true, 'history_mistreatment': false}, expected: CombinedPatternCondition.sunYangmingBase),
      (name: '少阳阳明下利滑数型', primary: '少阳', answers: {'constipated': true, 'diarrhea': true}, expected: CombinedPatternCondition.shaoyangYangmingBase),
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
          pulseType: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '滑'
              : null,
          pulseTypeSecondary: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '数'
              : null,
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
        expect(engine.combinedPatternCondition, scenario.expected);
        final rule = DiagnosticRules.combinedPatterns
            .firstWhere((pattern) => pattern.condition == scenario.expected);
        expect(result, isNotNull, reason: scenario.name);
        expect(result!.formula, rule.formula, reason: scenario.name);
        expect(result.recommendedFormulas, [rule.formula], reason: scenario.name);
        expect(result.pattern, rule.description, reason: scenario.name);
        expect(result.prescription?.formulaName, rule.formula, reason: scenario.name);
        expect(
        result.combinedMeridian,
        rule.isExplicitCombined ? isNotNull : isNull,
        reason: scenario.name,
      );
      });
    }

    test('规则表中的三条基础键没有检测器赋值路径，不得被误报为可达', () {
      final unreachable = <String>{
        CombinedPatternCondition.threeYangBase,
      };
      expect(cases.map((scenario) => scenario.expected).toSet().intersection(unreachable), isEmpty);
    });
  });

  group('旧六经兜底结果传播', () {
    test('未命中结构化规则时仍将精确合病方同步到最终处方', () {
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
      ));

      final result = engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangBase);
      expect(result, isNotNull);
      expect(result!.formula, '柴胡桂枝汤');
      expect(result.recommendedFormulas, ['柴胡桂枝汤']);
      // 旧六经兜底只验证方证结果传播；第146条不标记为明确合病。
      expect(result.pattern,
          '太阳表证未解，兼见少阳证：发热微恶寒、支节烦痛、微呕、心下支结');
      expect(result.combinedMeridian, isNull);
      expect(result.prescription?.formulaName, '柴胡桂枝汤');
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
