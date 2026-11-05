import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';

void main() {
  final cases = <({
    String key,
    String meridian,
    Map<String, dynamic> answers,
    String gateKey,
    String? pulse,
    String? secondary,
    Object? rejectedValue,
  })>[
    (
      key: CombinedPatternCondition.sunYangmingBase,
      meridian: '太阳',
      answers: {'constipated': true, 'diarrhea': true, 'history_mistreatment': false},
      gateKey: 'history_mistreatment',
      pulse: null,
      secondary: null,
      rejectedValue: true,
    ),
    (
      key: CombinedPatternCondition.sunShaoyangBase,
      meridian: '太阳',
      answers: {
        'temperature': 'fever_chills',
        'joint_pain': true,
        'clause146_mild_nausea': true,
        'illness_duration_6_7': true,
        'epigastric_fullness': true,
      },
      gateKey: 'illness_duration_6_7',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.shaoyangYangmingBase,
      meridian: '少阳',
      answers: {'constipated': true, 'diarrhea': true, 'food_stagnation': true},
      gateKey: 'food_stagnation',
      pulse: '滑',
      secondary: '数',
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.taiyinShaoyinBase,
      meridian: '太阴',
      answers: {'drowsy': true},
      gateKey: 'drowsy',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.sunYangmingVomit,
      meridian: '太阳',
      answers: {'constipated': true, 'diarrhea': false, 'nausea': true},
      gateKey: 'diarrhea',
      pulse: null,
      secondary: null,
      rejectedValue: true,
    ),
    (
      key: CombinedPatternCondition.sunYangmingChestFull,
      meridian: '太阳',
      answers: {'constipated': true, 'asthma': true, 'chest_fullness': true},
      gateKey: 'chest_fullness',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.sunShaoyangDiarrhea,
      meridian: '太阳',
      answers: {'bitter_mouth': true, 'diarrhea': true},
      gateKey: 'diarrhea',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.sunShaoyangVomit,
      meridian: '太阳',
      answers: {'bitter_mouth': true, 'diarrhea': true, 'nausea': true},
      gateKey: 'diarrhea',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.jueyinShaoyang,
      meridian: '厥阴',
      answers: {'bitter_mouth': true},
      gateKey: 'bitter_mouth',
      pulse: null,
      secondary: null,
      rejectedValue: false,
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
      gateKey: 'drowsy',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.shaoyangTaiyin,
      meridian: '少阳',
      answers: {
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
      },
      gateKey: 'illness_duration_5_6',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
    (
      key: CombinedPatternCondition.sunTaiyin,
      meridian: '太阳',
      answers: {
        'temperature': 'fever_chills',
        'fever': true,
        'has_sweat': false,
        'diarrhea': true,
        'history_mistreatment': true,
        'sun_taiyin_repeated_purgation': true,
        'epigastric_hard': true,
      },
      gateKey: 'epigastric_hard',
      pulse: null,
      secondary: null,
      rejectedValue: false,
    ),
  ];

  group('第256条脉象必须是滑数组合，单脉不能代替', () {
    DiagnosticEngine engineFor(String? primary, String? secondary) {
      return DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '少阳',
          answers: const {
            'constipated': true,
            'diarrhea': true,
            'food_stagnation': true,
            'headache': true,
          },
          tenQuestionIndex: 0,
          pulseType: primary,
          pulseTypeSecondary: secondary,
        ));
    }

    test('仅滑脉、仅数脉、同一脉重复及脉象未知均不得命中第256条', () {
      for (final pulses in <(String?, String?)>[
        ('滑', null),
        ('数', null),
        ('滑', '滑'),
        ('数', '数'),
        (null, null),
      ]) {
        final engine = engineFor(pulses.$1, pulses.$2);
        engine.diagnose();
        expect(
          engine.combinedPatternCondition,
          isNot(CombinedPatternCondition.shaoyangYangmingBase),
          reason: 'primary=${pulses.$1}, secondary=${pulses.$2}',
        );
      }
    });

    test('滑数与数滑两种录入顺序均可命中第256条', () {
      for (final pulses in <(String, String)>[
        ('滑', '数'),
        ('数', '滑'),
      ]) {
        final engine = engineFor(pulses.$1, pulses.$2);
        engine.diagnose();
        expect(
          engine.combinedPatternCondition,
          CombinedPatternCondition.shaoyangYangmingBase,
        );
      }
    });
  });

  group('合病矩阵负向可达性：缺失与冲突证据必须关闭规则', () {
    for (final item in cases) {
      for (final structured in [true, false]) {
        test('${item.key}：${structured ? '结构化主路径' : '旧兜底路径'}不得越过否定门槛', () {
          for (final rejected in <Object?>[item.rejectedValue, null]) {
            final engine = DiagnosticEngine()
              ..restoreSnapshot(EngineSnapshot(
                stage: DiagnosticStage.meridianLocation,
                selectedSymptoms: const [],
                meridianDirection: item.meridian,
                answers: {
                  ...item.answers,
                  item.gateKey: rejected,
                  'headache': true,
                  'palpitation': true,
                },
                tenQuestionIndex: 0,
                qAnswers: structured
                    ? const {
                        kQ1: 1,
                        kQ4: 2,
                        kQ2: 12,
                        kQ3: 1,
                        kQ5: 1,
                        kQ10: 2,
                      }
                    : const {},
                pulseType: item.pulse,
                pulseTypeSecondary: item.secondary,
              ));

            engine.diagnose();

            expect(
              engine.combinedPatternCondition,
              isNot(item.key),
              reason: '${item.key}, structured=$structured, ${item.gateKey}=$rejected',
            );
          }
        });
      }
    }
  });
}
