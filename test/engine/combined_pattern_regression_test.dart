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
          'hot_palms_soles': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
      ));

      // 无扁平规则答案时进入旧六经路径；无论旧路径是否有足够结果，
      // 合病条件必须由新分支确定为下利热，而不能被一般太阳阳明分支截获。
      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunYangmingDiarrheaHeat);
    });
  });
}
