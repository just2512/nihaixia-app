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
        CombinedPatternCondition.taiyinShaoyinBase,
        CombinedPatternCondition.sunYangmingVomit,
        CombinedPatternCondition.sunYangmingChestFull,
        CombinedPatternCondition.sunShaoyangDiarrhea,
        CombinedPatternCondition.sunShaoyangVomit,
        CombinedPatternCondition.jueyinShaoyang,
        CombinedPatternCondition.threeYangSleep,
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

  group('第146条单经方证进入结构化主路径', () {
    test('RuleEngine 命中第146条方证时使用柴胡桂枝汤且不标记为明文合病', () {
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
          'joint_pain': true,
          'clause146_mild_nausea': true,
          'illness_duration_6_7': true,
          'epigastric_fullness': true,
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
      // 第146条是太阳表证兼少阳证，不能因使用柴胡桂枝汤而标记为明文合病。
      expect(result.combinedMeridian, isNull);
      expect(result.pattern, contains('第146条'));
      expect(result.pattern, contains('非明文合病'));
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
          'joint_pain': true,
          'clause146_mild_nausea': true,
          'illness_duration_6_7': true,
          'epigastric_fullness': true,
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
      expect(result.formula, isNot('葛根黄芩黄连汤'));
    });

    test('第34条误下协热利必须同时满足原文关键证据', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'fever': true,
          'has_sweat': true,
          'history_mistreatment': true,
          'diarrhea': true,
          'asthma': true,
          'breathing': '喘',
        },
        tenQuestionIndex: 0,
        pulseType: '促',
      ));

      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.formula, '葛根黄芩黄连汤');
      expect(result.pattern, contains('太阳病误下协热利'));
      expect(result.meridian, '太阳');
      expect(result.combinedMeridian, isNull);
    });

    test('第34条特异证据优先于第178条协热下利心下痞硬', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const ['协热下利', '心下痞硬'],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'fever': true,
          'has_sweat': true,
          'history_mistreatment': true,
          'diarrhea': true,
          'asthma': true,
        },
        tenQuestionIndex: 0,
        pulseType: '促',
      ));

      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.formula, '葛根黄芩黄连汤');
      expect(result.pattern, contains('葛根黄芩黄连汤证'));
    });

    test('第34条缺少喘或汗出证据时不得触发葛根黄芩黄连汤', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'fever': true,
          'has_sweat': false,
          'history_mistreatment': true,
          'diarrhea': true,
          'asthma': false,
        },
        tenQuestionIndex: 0,
        pulseType: '促',
      ));

      final result = engine.diagnose();
      expect(result, isNotNull);
      expect(result!.formula, isNot('葛根黄芩黄连汤'));
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
          'three_yang_pulse_position_answered': true,
          'three_yang_pulse_position_confirmed': true,
        },
        tenQuestionIndex: 0,
        pulseType: '浮',
        pulseTypeSecondary: '大',
      ));

      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.threeYangSleep);
    });
  });

  group('第256条宿食证据门槛', () {
    test('少阳阳明候选合病且滑数脉时追问食积，不直接命中大承气汤', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
        pulseType: '滑',
        pulseTypeSecondary: '数',
      ));

      expect(engine.meridianDirection, '少阳');
      final questions = engine.getFollowUpQuestions(engine.meridianDirection!);
      expect(questions.any((q) => q.key == 'food_stagnation'), isTrue);
      engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
    });

    test('明确食积证据回答后才允许第256条条件命中', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
        pulseType: '滑',
        pulseTypeSecondary: '数',
      ));

      engine.answerFollowUp('food_stagnation', '有明确食积表现');
      engine.diagnose();
      expect(
        engine.combinedPatternCondition,
        CombinedPatternCondition.shaoyangYangmingBase,
      );
    });

    test('食积回答为不确定时仍保持拒绝状态', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
        pulseType: '滑',
        pulseTypeSecondary: '数',
      ));

      engine.answerFollowUp('food_stagnation', '不确定');
      engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
      expect(
        engine.getFollowUpQuestions('少阳').any((q) => q.key == 'food_stagnation'),
        isFalse,
      );
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


  group('合病条文前提的问诊可达性', () {
    test('太阳阳明下利候选必须在结果前追问误下史', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
      ));

      final questions = engine.getRequiredCombinedPatternFollowUpQuestions();
      expect(questions.map((question) => question.key),
          contains('combined_treatment_history'));
      engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
    });

    test('误下史回答不确定时不触发第32条，也不重复追问', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
      ));

      engine.answerFollowUp('combined_treatment_history', '不确定');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions(), isEmpty);
      engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
    });

    test('明确无误下史回答后才允许第32条条件命中', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
      ));

      engine.answerFollowUp('combined_treatment_history', '明确没有');
      engine.diagnose();
      expect(
        engine.combinedPatternCondition,
        CombinedPatternCondition.sunYangmingBase,
      );
    });

    test('太阳转太阴第163条必须核对反复误下与心下痞硬', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'has_sweat': true,
          'diarrhea': true,
          'abdominal_pain': true,
        },
        tenQuestionIndex: 0,
      ));

      expect(
        engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
        'combined_treatment_history',
      );
      engine.answerFollowUp('combined_treatment_history', '曾经被误用泻下法');
      expect(engine.selectedSymptoms, isEmpty);
      expect(
        engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
        'sun_taiyin_repeated_purgation',
      );
      engine.answerFollowUp('sun_taiyin_repeated_purgation', '曾多次使用');
      expect(engine.selectedSymptoms, isEmpty);
      expect(
        engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
        'sun_taiyin_epigastric_hard',
      );
      engine.answerFollowUp('sun_taiyin_epigastric_hard', '有心下痞硬');

      engine.diagnose();
      expect(
        engine.combinedPatternCondition,
        CombinedPatternCondition.sunTaiyin,
      );
    });

    test('第256条候选在最终结果前进入宿食追问', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
        pulseType: '滑',
        pulseTypeSecondary: '数',
      ));

      expect(
        engine.getRequiredCombinedPatternFollowUpQuestions()
            .map((question) => question.key),
        contains('food_stagnation'),
      );
      engine.answerFollowUp('food_stagnation', '不确定');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions(), isEmpty);
      engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
    });
  });

  group('合病检测器可达性矩阵', () {
    final cases = <({String name, String primary, Map<String, dynamic> answers, String expected})>[
      (name: '太阳少阳基础型', primary: '太阳', answers: {'temperature': 'fever_chills', 'joint_pain': true, 'clause146_mild_nausea': true, 'illness_duration_6_7': true, 'epigastric_fullness': true}, expected: CombinedPatternCondition.sunShaoyangBase),
      (name: '太阴少阴基础型', primary: '太阴', answers: {'drowsy': true}, expected: CombinedPatternCondition.taiyinShaoyinBase),
      (name: '太阳阳明呕吐型', primary: '太阳', answers: {'constipated': true, 'diarrhea': false, 'vomiting': true}, expected: CombinedPatternCondition.sunYangmingVomit),
      (name: '太阳阳明胸满型', primary: '太阳', answers: {'constipated': true, 'asthma': true, 'chest_fullness': true}, expected: CombinedPatternCondition.sunYangmingChestFull),
      (name: '太阳少阳下利型', primary: '太阳', answers: {'bitter_mouth': true, 'diarrhea': true}, expected: CombinedPatternCondition.sunShaoyangDiarrhea),
      (name: '太阳少阳呕吐型', primary: '太阳', answers: {'bitter_mouth': true, 'diarrhea': true, 'vomiting': true}, expected: CombinedPatternCondition.sunShaoyangVomit),
      (name: '厥阴少阳型', primary: '厥阴', answers: {'bitter_mouth': true}, expected: CombinedPatternCondition.jueyinShaoyang),
      (name: '三阳但欲寐型', primary: '太阳', answers: {'thirsty': true, 'bitter_mouth': true, 'drowsy': true, 'has_sweat': true, 'three_yang_pulse_position_answered': true, 'three_yang_pulse_position_confirmed': true}, expected: CombinedPatternCondition.threeYangSleep),
      (name: '第147条少阳方证', primary: '少阳', answers: {'illness_duration_5_6': true, 'shaoyang147_prior_sweat_then_purge': true, 'chest_minor_knot': true, 'urine_difficult': true, 'thirsty': true, 'nausea': false, 'vomiting': false, 'head_sweat': true, 'alternating_chills': true, 'irritable': true}, expected: CombinedPatternCondition.shaoyangTaiyin),
      (name: '第163条太阳误下后协热利', primary: '太阳', answers: {'temperature': 'fever_chills', 'diarrhea': true, 'history_mistreatment': true, 'sun_taiyin_repeated_purgation': true, 'epigastric_hard': true}, expected: CombinedPatternCondition.sunTaiyin),
      (name: '太阳阳明下利基础型', primary: '太阳', answers: {'constipated': true, 'diarrhea': true, 'history_mistreatment': false}, expected: CombinedPatternCondition.sunYangmingBase),
      (name: '少阳阳明下利滑数且有食积型', primary: '少阳', answers: {'constipated': true, 'diarrhea': true, 'food_stagnation': true}, expected: CombinedPatternCondition.shaoyangYangmingBase),
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
              : scenario.expected == CombinedPatternCondition.threeYangSleep
                  ? '浮'
                  : null,
          pulseTypeSecondary: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '数'
              : scenario.expected == CombinedPatternCondition.threeYangSleep
                  ? '大'
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
        final diagnosis = result!;
        expect(diagnosis.formula, rule.formula, reason: scenario.name);
        expect(diagnosis.pattern, rule.description, reason: scenario.name);
        if (rule.formula.isEmpty) {
          expect(diagnosis.recommendedFormulas, isEmpty, reason: scenario.name);
          expect(diagnosis.prescription, isNull, reason: scenario.name);
          expect(diagnosis.recommendConsult, isTrue, reason: scenario.name);
        } else {
          expect(diagnosis.recommendedFormulas, [rule.formula], reason: scenario.name);
          expect(diagnosis.prescription?.formulaName, rule.formula, reason: scenario.name);
        }
        expect(
        result.combinedMeridian,
        rule.isExplicitCombined ? isNotNull : isNull,
        reason: scenario.name,
      );
      });
    }

    for (final scenario in cases) {
      test('${scenario.name} 旧六经兜底路径同步应用精确合病方', () {
        final engine = DiagnosticEngine();
        engine.restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: scenario.primary,
          // 两个与合病检测无关的已记录线索，确保旧路径越过“证据不足”闸；
          // 不参与条件键生成，避免测试把证据闸误当成路径不可达。
          answers: {
            'insomnia': true,
            'edema': true,
            ...scenario.answers,
          },
          tenQuestionIndex: 0,
          pulseType: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '滑'
              : scenario.expected == CombinedPatternCondition.threeYangSleep
                  ? '浮'
                  : null,
          pulseTypeSecondary: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '数'
              : scenario.expected == CombinedPatternCondition.threeYangSleep
                  ? '大'
                  : null,
        ));

        final result = engine.diagnose();
        final rule = DiagnosticRules.combinedPatterns
            .firstWhere((pattern) => pattern.condition == scenario.expected);
        expect(engine.combinedPatternCondition, scenario.expected,
            reason: scenario.name);
        expect(result, isNotNull, reason: scenario.name);
        final diagnosis = result!;
        expect(diagnosis.formula, rule.formula, reason: scenario.name);
        expect(diagnosis.pattern, rule.description, reason: scenario.name);
        if (rule.formula.isEmpty) {
          expect(diagnosis.recommendedFormulas, isEmpty, reason: scenario.name);
          expect(diagnosis.prescription, isNull, reason: scenario.name);
          expect(diagnosis.recommendConsult, isTrue, reason: scenario.name);
        } else {
          expect(diagnosis.recommendedFormulas, [rule.formula], reason: scenario.name);
          expect(diagnosis.prescription?.formulaName, rule.formula, reason: scenario.name);
        }
        expect(
          result.combinedMeridian,
          rule.isExplicitCombined ? isNotNull : isNull,
          reason: scenario.name,
        );
      });
    }

    test('旧杂病兜底先命中五苓散时仍应用精确合病表方', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const ['水入即吐'],
        meridianDirection: '太阳',
        answers: const {
          'thirsty': true,
          'urine_difficult': true,
          'hot_palms_soles': true,
          'diarrhea': true,
          'history_mistreatment': false,
        },
        tenQuestionIndex: 0,
      ));

      // 该快照同时满足旧杂病兜底的五苓散入口和第32条合病条件；
      // 这里只验证结果组装优先级，不表示该组症状在临床上应被视为同一方证。
      final result = engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunYangmingBase);
      expect(result, isNotNull);
      expect(result!.formula, '葛根汤');
      expect(result.recommendedFormulas, ['葛根汤']);
      expect(result.combinedMeridian, '阳明');
      expect(result.prescription?.formulaName, '葛根汤');
    });

    for (final scenario in cases) {
      test('${scenario.name} 旧杂病兜底路径同步应用精确合病方', () {
        final engine = DiagnosticEngine();
        engine.restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const ['少腹硬满', '发狂'],
          meridianDirection: scenario.primary,
          // 以确定命中旧杂病兜底的蓄血分支为路径标记；这些症状不参与合病条件生成。
          answers: {
            ...scenario.answers,
          },
          tenQuestionIndex: 0,
          pulseType: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '滑'
              : scenario.expected == CombinedPatternCondition.threeYangSleep
                  ? '浮'
                  : null,
          pulseTypeSecondary: scenario.expected == CombinedPatternCondition.shaoyangYangmingBase
              ? '数'
              : scenario.expected == CombinedPatternCondition.threeYangSleep
                  ? '大'
                  : null,
        ));

        final result = engine.diagnose();
        final rule = DiagnosticRules.combinedPatterns
            .firstWhere((pattern) => pattern.condition == scenario.expected);
        expect(engine.combinedPatternCondition, scenario.expected,
            reason: scenario.name);
        expect(result, isNotNull, reason: scenario.name);
        // 若旧杂病分支没有先被命中，基础六经分支的输出/处方链可能掩盖路径缺口。
        final diagnosis = result!;
        expect(diagnosis.formula, rule.formula, reason: scenario.name);
        expect(diagnosis.pattern, rule.description, reason: scenario.name);
        if (rule.formula.isEmpty) {
          expect(diagnosis.recommendedFormulas, isEmpty, reason: scenario.name);
          expect(diagnosis.prescription, isNull, reason: scenario.name);
          expect(diagnosis.recommendConsult, isTrue, reason: scenario.name);
        } else {
          expect(diagnosis.recommendedFormulas, [rule.formula], reason: scenario.name);
          expect(diagnosis.prescription?.formulaName, rule.formula, reason: scenario.name);
        }
        expect(
          result.combinedMeridian,
          rule.isExplicitCombined ? isNotNull : isNull,
          reason: scenario.name,
        );
      });
    }

    test('第256条证据不足时不误触发第147条少阳方证', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
          'abdominal_pain': true,
          // 故意缺少宿食证据；也未提供滑数组合脉。
        },
        tenQuestionIndex: 0,
      ));

      engine.diagnose();
      expect(engine.combinedPatternCondition, isNull);
      expect(engine.createSnapshot().combinedMeridian, isNull);
    });

    test('太阳阳明下利误下史为真时不遮蔽太阳少阳候选', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
          'history_mistreatment': true,
          'bitter_mouth': true,
        },
        tenQuestionIndex: 0,
      ));

      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangDiarrhea);
      expect(engine.createSnapshot().combinedMeridian, '少阳');
    });

    test('误下史未知时不得误命中第32条葛根汤合病', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'constipated': true,
          'diarrhea': true,
        },
        tenQuestionIndex: 0,
      ));

      engine.diagnose();
      expect(engine.combinedPatternCondition,
          isNot(CombinedPatternCondition.sunYangmingBase));
    });

    test('规则表与检测器可达矩阵数量一致，唯一死键不得被误报为可达', () {
      final ruleConditions = DiagnosticRules.combinedPatterns
          .map((pattern) => pattern.condition)
          .toSet();
      final reachableConditions =
          cases.map((scenario) => scenario.expected).toSet();
      final unreachable = ruleConditions.difference(reachableConditions);

      expect(DiagnosticRules.combinedPatterns, hasLength(12));
      expect(ruleConditions, hasLength(12));
      expect(reachableConditions, hasLength(12));
      expect(unreachable, isEmpty);
      expect(ruleConditions, isNot(contains(CombinedPatternCondition.threeYangBase)));
      expect(ruleConditions, isNot(contains(CombinedPatternCondition.sunYangmingUnresolved)));
      expect(ruleConditions, isNot(contains(CombinedPatternCondition.sunShaoyinTwoCold)));
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
          'joint_pain': true,
          'clause146_mild_nausea': true,
          'illness_duration_6_7': true,
          'epigastric_fullness': true,
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
          '伤寒六七日，发热微恶寒、支节烦疼、微呕、心下支结、外证未去（第146条；非明文合病）');
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
      expect(engine.combinedPatternCondition, isNull);
      expect(result, isNotNull);
      expect(result!.formula, isNot('柴胡桂枝汤'));
      expect(result.combinedMeridian, isNull);
    });
  });


    test('第146条追问答案正确生成支节烦疼、微呕、心下支结证据', () {
      final engine = DiagnosticEngine();
      engine.answerFollowUp('body_pain', '支节烦疼（第146条线索）');
      engine.answerFollowUp('clause146_mild_nausea', '有微呕/恶心（第146条线索）');
      engine.answerFollowUp('illness_duration', '约6—7天（第146条）');
      engine.answerFollowUp('chest', '心下支结（第146条线索）');
      final answers = engine.createSnapshot().answers;
      expect(answers['joint_pain'], isTrue);
      expect(answers['clause146_mild_nausea'], isTrue);
      expect(answers['illness_duration_6_7'], isTrue);
      expect(answers['epigastric_fullness'], isTrue);
    });

    test('第147条追问答案正确生成误汗复下、头汗及不呕证据', () {
      final engine = DiagnosticEngine();
      engine.answerFollowUp('shaoyang147_treatment_sequence', '先发汗后又误下');
      engine.answerFollowUp('chest', '胸胁满+微结（→柴胡桂枝干姜汤）');
      engine.answerFollowUp('sweating', '但头汗出');
      engine.answerFollowUp('nausea', '不想吐');
      engine.answerFollowUp('illness_duration', '约5—6天（第147条）');
      final answers = engine.createSnapshot().answers;
      expect(answers['shaoyang147_prior_sweat_then_purge'], isTrue);
      expect(answers['chest_minor_knot'], isTrue);
      expect(answers['head_sweat'], isTrue);
      expect(answers['has_sweat'], isTrue);
      expect(answers['nausea'], isFalse);
      expect(answers['illness_duration_5_6'], isTrue);
    });

  group('原文条件与单经证分类', () {

    test('第146条候选按顺序追问微呕和病程天数', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'joint_pain': true,
          'epigastric_fullness': true,
        },
        tenQuestionIndex: 0,
      ));
      expect(engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
          'clause146_mild_nausea');
      engine.answerFollowUp(
          'clause146_mild_nausea', '有微呕/恶心（第146条线索）');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
          'illness_duration');
      engine.answerFollowUp('illness_duration', '约6—7天（第146条）');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions(), isEmpty);
      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangBase);
    });

    test('第147条候选按顺序追问不呕、误汗复下和病程天数', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阳',
        answers: const {
          'chest_minor_knot': true,
          'urine_difficult': true,
          'thirsty': true,
          'head_sweat': true,
          'alternating_chills': true,
          'irritable': true,
        },
        tenQuestionIndex: 0,
      ));
      expect(engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
          'nausea');
      engine.answerFollowUp('nausea', '不想吐');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
          'shaoyang147_treatment_sequence');
      engine.answerFollowUp(
          'shaoyang147_treatment_sequence', '先发汗后又误下');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions().single.key,
          'illness_duration');
      engine.answerFollowUp('illness_duration', '约5—6天（第147条）');
      expect(engine.getRequiredCombinedPatternFollowUpQuestions(), isEmpty);
      final result = engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.shaoyangTaiyin);
      expect(result, isNotNull);
      expect(result!.formula, '柴胡桂枝干姜汤');
    });

    test('第146条缺少支节烦疼、微呕、心下支结时不触发柴胡桂枝汤', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'bitter_mouth': true,
          'dry_throat': true,
        },
        tenQuestionIndex: 0,
      ));
      engine.diagnose();
      expect(engine.combinedPatternCondition,
          isNot(CombinedPatternCondition.sunShaoyangBase));
    });

    test('第147条必须逐项满足原文前提才可触发柴胡桂枝干姜汤', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
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
          'head_sweat': true,
          'alternating_chills': true,
          'irritable': true,
        },
        tenQuestionIndex: 0,
      ));
      final result = engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.shaoyangTaiyin);
      expect(result, isNotNull);
      expect(result!.formula, '柴胡桂枝干姜汤');
      expect(result.combinedMeridian, isNull);
    });

    test('第301条从少阴兼表路径出方，不进入合病表', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '少阴',
        answers: const {'shaoyin_with_table': true},
        tenQuestionIndex: 0,
        pulseType: '沉',
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
      expect(engine.combinedPatternCondition, isNull);
      expect(result, isNotNull);
      expect(result!.formula, '麻黄附子细辛汤');
      expect(result.combinedMeridian, isNull);
    });
  });

  group('特异方证优先级与分支遮蔽', () {
    test('第146条完整证据优先于太阳阳明呕吐宽泛分支', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
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
          'nausea': true,
          'bitter_mouth': true,
        },
        tenQuestionIndex: 0,
      ));
      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunShaoyangBase);
    });

    test('第147条完整证据优先于少阳阳明下利滑数脉分支', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
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
        tenQuestionIndex: 0,
        pulseType: '滑',
        pulseTypeSecondary: '数',
      ));
      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.shaoyangTaiyin);
    });

    test('第163条完整证据优先于太阳少阳下利宽泛分支', () {
      final engine = DiagnosticEngine();
      engine.restoreSnapshot(EngineSnapshot(
        stage: DiagnosticStage.meridianLocation,
        selectedSymptoms: const [],
        meridianDirection: '太阳',
        answers: const {
          'temperature': 'fever_chills',
          'diarrhea': true,
          'history_mistreatment': true,
          'sun_taiyin_repeated_purgation': true,
          'epigastric_hard': true,
          'bitter_mouth': true,
        },
        tenQuestionIndex: 0,
      ));
      engine.diagnose();
      expect(engine.combinedPatternCondition,
          CombinedPatternCondition.sunTaiyin);
    });
  });

}
