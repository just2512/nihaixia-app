import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/services/tcm_interview_adapter.dart';

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
    Map<String, String> promptAnswers,
  })>[
    (
      key: CombinedPatternCondition.sunYangmingBase,
      meridian: '太阳',
      answers: {'constipated': true, 'diarrhea': true},
      pulse: null,
      secondary: null,
      promptAnswers: {'combined_treatment_history': '明确没有'},
    ),
    (
      key: CombinedPatternCondition.sunShaoyangBase,
      meridian: '太阳',
      answers: {
        'temperature': 'fever_chills',
        'joint_pain': true,
        'epigastric_fullness': true,
      },
      pulse: null,
      secondary: null,
      promptAnswers: {
        'clause146_mild_nausea': '有微呕/恶心（第146条线索）',
        'illness_duration': '约6—7天（第146条）',
      },
    ),
    (
      key: CombinedPatternCondition.shaoyangYangmingBase,
      meridian: '少阳',
      answers: {'constipated': true, 'diarrhea': true},
      pulse: '滑',
      secondary: '数',
      promptAnswers: {'food_stagnation': '有明确食积表现'},
    ),
    (
      key: CombinedPatternCondition.taiyinShaoyinBase,
      meridian: '太阴',
      answers: {'drowsy': true},
      pulse: null,
      secondary: null,
      promptAnswers: {},
    ),
    (
      key: CombinedPatternCondition.sunYangmingVomit,
      meridian: '太阳',
      answers: {'constipated': true, 'nausea': true},
      pulse: null,
      secondary: null,
      promptAnswers: {'combined_diarrhea_status': '明确没有下利（第33条）'},
    ),
    (
      key: CombinedPatternCondition.sunYangmingChestFull,
      meridian: '太阳',
      answers: {'constipated': true, 'asthma': true},
      pulse: null,
      secondary: null,
      promptAnswers: {'combined_clause36_chest_fullness': '有胸满（第36条）'},
    ),
    (
      key: CombinedPatternCondition.sunShaoyangDiarrhea,
      meridian: '太阳',
      answers: {'bitter_mouth': true, 'diarrhea': true},
      pulse: null,
      secondary: null,
      promptAnswers: {'combined_treatment_history': '明确没有'},
    ),
    (
      key: CombinedPatternCondition.sunShaoyangVomit,
      meridian: '太阳',
      answers: {'bitter_mouth': true, 'nausea': true},
      pulse: null,
      secondary: null,
      promptAnswers: {
        'combined_clause172_diarrhea': '明确有自下利（第172条）',
        'combined_treatment_history': '明确没有',
      },
    ),
    (
      key: CombinedPatternCondition.jueyinShaoyang,
      meridian: '厥阴',
      answers: {'bitter_mouth': true},
      pulse: null,
      secondary: null,
      promptAnswers: {},
    ),
    (
      key: CombinedPatternCondition.threeYangSleep,
      meridian: '太阳',
      answers: {
        'thirsty': true,
        'bitter_mouth': true,
        'drowsy': true,
        'has_sweat': true,
      },
      pulse: '浮',
      secondary: '大',
      promptAnswers: {
        'three_yang_pulse_position': '已由专业人员确认',
      },
    ),
    (
      key: CombinedPatternCondition.shaoyangTaiyin,
      meridian: '少阳',
      answers: {
        'chest_minor_knot': true,
        'urine_difficult': true,
        'thirsty': true,
        'head_sweat': true,
        'alternating_chills': true,
        'irritable': true,
      },
      pulse: null,
      secondary: null,
      promptAnswers: {
        'nausea': '不想吐',
        'shaoyang147_treatment_sequence': '先发汗后又误下',
        'illness_duration': '约5—6天（第147条）',
      },
    ),
    (
      key: CombinedPatternCondition.sunTaiyin,
      meridian: '太阳',
      answers: {
        'temperature': 'fever_chills',
        'has_sweat': false,
        'diarrhea': true,
        'history_mistreatment': true,
      },
      pulse: null,
      secondary: null,
      promptAnswers: {
        'sun_taiyin_repeated_purgation': '曾多次使用',
        'sun_taiyin_epigastric_hard': '有心下痞硬',
      },
    ),
  ];

  group('合病条件从适配层追问产生并进入最终规则结果', () {
    for (final item in cases) {
      test('${item.key}：按引擎实际提示逐项回答后命中最终规则', () {
        final adapter = TcmInterviewAdapter(
          snapshot: EngineSnapshot(
            stage: DiagnosticStage.meridianLocation,
            selectedSymptoms: const [],
            meridianDirection: item.meridian,
            answers: {...item.answers},
            tenQuestionIndex: 0,
            qAnswers: const {
              kQ1: 1,
              kQ4: 2,
              kQ2: 12,
              kQ3: 1,
              kQ5: 1,
              kQ10: 2,
            },
            pulseType: item.pulse,
            pulseTypeSecondary: item.secondary,
          ),
        );

        final seenPrompts = <String>[];
        for (var attempt = 0; attempt < 10; attempt++) {
          final prompts = adapter.requiredCombinedPatternChecks;
          if (prompts.isEmpty) break;
          final prompt = prompts.first;
          final answer = item.promptAnswers[prompt.id];
          expect(
            answer,
            isNotNull,
            reason: '${item.key} produced an unplanned required prompt ${prompt.id}',
          );
          seenPrompts.add(prompt.id);
          adapter.answerFollowUp(prompt.id, answer!);
        }

        expect(
          seenPrompts.toSet(),
          item.promptAnswers.keys.toSet(),
          reason: '${item.key} must produce every expected prompt exactly once',
        );
        expect(adapter.requiredCombinedPatternChecks, isEmpty);

        final diagnosis = adapter.diagnose();
        final expected = DiagnosticRules.combinedPatterns.singleWhere(
          (pattern) => pattern.condition == item.key,
        );
        expect(adapter.combinedPatternCondition, item.key);
        expect(diagnosis, isNotNull);
        expect(diagnosis!.pattern, expected.description);
        expect(diagnosis.formula, expected.formula);
        if (expected.formula.isEmpty) {
          expect(diagnosis.recommendedFormulas, isEmpty);
          expect(diagnosis.prescription, isNull);
          expect(diagnosis.recommendConsult, isTrue);
        } else {
          expect(diagnosis.recommendedFormulas, [expected.formula]);
          expect(diagnosis.prescription?.formulaName, expected.formula);
        }
        expect(
          diagnosis.combinedMeridian,
          expected.isExplicitCombined ? isNotNull : isNull,
        );
      });
    }
  });
}
