import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/services/tcm_interview_adapter.dart';

void main() {
  group('TcmInterviewAdapter', () {
    test('温病/寒热问题只暴露诊断引擎已有的规范 key', () {
      final adapter = TcmInterviewAdapter();
      expect(
        adapter.temperatureOptions.map((option) => option.key).toList(),
        DiagnosticRules.temperaturePatterns.map((option) => option.key).toList(),
      );
    });

    test('拒绝不存在的辨经 key', () {
      final adapter = TcmInterviewAdapter();
      expect(
        () => adapter.answerTemperature('invented_pattern'),
        throwsArgumentError,
      );
    });

    test('舌脉选项来自 canonical 引擎选项，组合脉保留主兼关系', () {
      final adapter = TcmInterviewAdapter();
      expect(adapter.tongueCoatingOptions, isNotEmpty);
      expect(adapter.tongueShapeOptions, isNotEmpty);
      expect(adapter.pulseOptions, isNotEmpty);

      adapter.answerTonguePulse(
        tongueCoating: '白厚',
        tongueShape: '淡白',
        primaryPulse: '弦',
        secondaryPulse: '滑',
      );
      final restored = TcmInterviewAdapter(snapshot: adapter.createSnapshot());
      expect(restored.createSnapshot().tongueCoating, '白厚');
      expect(restored.createSnapshot().tongueShape, '淡白');
      expect(restored.createSnapshot().pulseType, '弦');
      expect(restored.createSnapshot().pulseTypeSecondary, '滑');
    });

    test('舌脉边界拒绝未知值和把组合脉误写成单脉', () {
      final adapter = TcmInterviewAdapter();
      expect(
        () => adapter.answerTonguePulse(tongueCoating: '不存在的舌苔'),
        throwsArgumentError,
      );
      expect(
        () => adapter.answerTonguePulse(primaryPulse: '浮数'),
        throwsArgumentError,
      );
      expect(
        () => adapter.answerTonguePulse(
          primaryPulse: '弦',
          secondaryPulse: '不存在的兼脉',
        ),
        throwsArgumentError,
      );
    });

    test('主脉与兼脉都参与脉舌冲突交叉核验', () {
      final adapter = TcmInterviewAdapter();
      adapter.answerTonguePulse(
        tongueCoating: '白厚',
        tongueShape: '淡白',
        primaryPulse: '弦',
        secondaryPulse: '数',
      );

      final questionIds = adapter.pulseTongueCrossChecks
          .map((prompt) => prompt.id)
          .toSet();
      expect(
        questionIds,
        containsAll([
          'pulse_cross_drink',
          'pulse_cross_urine',
          'pulse_cross_limbs',
          'pulse_cross_shaoyang',
          'pulse_cross_taiyin',
        ]),
      );
    });

    test('部分少阳线索为阴性不代表咽干已回答，仍须追问', () {
      final adapter = TcmInterviewAdapter(
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'bitter_mouth': false,
            'alternating_chills': false,
          },
          tenQuestionIndex: 0,
          tongueCoating: '白厚',
          tongueShape: '淡白',
          pulseType: '弦',
        ),
      );

      expect(
        adapter.pulseTongueCrossChecks.map((prompt) => prompt.id),
        contains('pulse_cross_shaoyang'),
      );
      expect(
        adapter.createSnapshot().answers.containsKey('dry_throat'),
        isFalse,
      );
    });

    test('少阳相关三项线索全部明确回答阴性后不重复追问', () {
      final adapter = TcmInterviewAdapter(
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'bitter_mouth': false,
            'dry_throat': false,
            'alternating_chills': false,
          },
          tenQuestionIndex: 0,
          tongueCoating: '白厚',
          tongueShape: '淡白',
          pulseType: '弦',
        ),
      );

      expect(
        adapter.pulseTongueCrossChecks.map((prompt) => prompt.id),
        isNot(contains('pulse_cross_shaoyang')),
      );
    });

    test('舌脉解释性标签在边界处归一为 canonical 值', () {
      final adapter = TcmInterviewAdapter();
      adapter.answerTonguePulse(
        tongueCoating: '白厚（舌苔）',
        primaryPulse: '微弱（脉象）',
      );
      final snapshot = adapter.createSnapshot();
      expect(snapshot.tongueCoating, '白厚');
      expect(snapshot.pulseType, '微弱');
    });

    test('第172条呕吐候选缺少自下利证据时由适配层追问', () {
      final adapter = TcmInterviewAdapter(
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'bitter_mouth': true,
            'nausea': true,
            'headache': true,
          },
          tenQuestionIndex: 0,
        ),
      );

      final prompts = adapter.requiredCombinedPatternChecks;
      expect(prompts, hasLength(1));
      expect(prompts.single.id, 'combined_clause172_diarrhea');
      expect(prompts.single.options, contains('明确有自下利（第172条）'));
      adapter.answerFollowUp(
        prompts.single.id,
        '明确有自下利（第172条）',
      );
      final diagnosis = adapter.diagnose();
      expect(
        adapter.combinedPatternCondition,
        CombinedPatternCondition.sunShaoyangVomit,
      );
      expect(diagnosis?.formula, '黄芩加半夏生姜汤');
    });

    test('第33条无下利前提通过统一问诊适配层显式确认', () {
      final adapter = TcmInterviewAdapter(
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {
            'constipated': true,
            'nausea': true,
            'headache': true,
          },
          tenQuestionIndex: 0,
        ),
      );

      final prompts = adapter.requiredCombinedPatternChecks;
      expect(prompts, hasLength(1));
      expect(prompts.single.id, 'combined_diarrhea_status');
      expect(prompts.single.options, contains('明确没有下利（第33条）'));
      expect(
        () => adapter.answerFollowUp(
          prompts.single.id,
          '随便回答',
        ),
        throwsArgumentError,
      );

      adapter.answerFollowUp(
        prompts.single.id,
        '明确没有下利（第33条）',
      );
      final result = adapter.diagnose();
      expect(adapter.combinedPatternCondition,
          CombinedPatternCondition.sunYangmingVomit);
      expect(result?.formula, '葛根加半夏汤');
    });

    test('脉舌冲突追问经适配层生成、校验并随快照恢复', () {
      final adapter = TcmInterviewAdapter();
      adapter.answerTemperature('fever_chills');
      adapter.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        primaryPulse: '数',
      );

      final initial = adapter.pulseTongueCrossChecks;
      expect(
        initial.map((prompt) => prompt.id),
        containsAll([
          'pulse_cross_drink',
          'pulse_cross_urine',
          'pulse_cross_limbs',
        ]),
      );
      final drink = initial.firstWhere((prompt) => prompt.id == 'pulse_cross_drink');
      expect(
        () => adapter.answerFollowUp(drink.id, '不在选项内的答案'),
        throwsArgumentError,
      );
      adapter.answerFollowUp(drink.id, '口渴，喜热饮');
      adapter.answerFollowUp('pulse_cross_urine', '清长色淡');
      adapter.answerFollowUp('pulse_cross_limbs', '偏冷');

      final restored = TcmInterviewAdapter(snapshot: adapter.createSnapshot());
      expect(restored.pulseTongueCrossChecks, isEmpty);
      final result = restored.diagnose();
      expect(result, isNotNull);
      expect(
        result!.pulseTongueAssessment!.supportingEvidence,
        containsAll(['喜热饮', '小便清长', '四肢偏冷']),
      );
      expect(
        result.pulseTongueContradiction,
        contains('不自动以脉或舌单方优先'),
      );
    });

    test('十问答案必须与引擎规范选项完全一致', () {
      final adapter = TcmInterviewAdapter();
      final first = adapter.tenQuestionPrompts.first;
      expect(
        () => adapter.answerTenQuestion(first.id, '任意自然语言直接写入'),
        throwsArgumentError,
      );
      expect(
        () => adapter.answerTenQuestion(first.id, first.options.first),
        returnsNormally,
      );
    });

    test('历史恢复后不重新询问已经配置的性别', () {
      final engine = DiagnosticEngine();
      engine.getTenQuestions(defaultGender: 'male');
      final adapter = TcmInterviewAdapter(snapshot: engine.createSnapshot());
      final ids = adapter.tenQuestionPrompts.map((prompt) => prompt.id);
      expect(ids, isNot(contains('gender')));
      expect(ids, isNot(contains('menstrual')));
    });

    test('历史快照恢复后继续使用原来的引擎状态', () {
      final original = TcmInterviewAdapter();
      final first = original.tenQuestionPrompts.first;
      original.answerTenQuestion(first.id, first.options.first);
      final restored = TcmInterviewAdapter(snapshot: original.createSnapshot());

      expect(restored.questionIndex, original.questionIndex);
      expect(restored.createSnapshot().answers, original.createSnapshot().answers);
    });

    test('脏腑证据通过独立只读接口暴露', () {
      final adapter = TcmInterviewAdapter();
      final evidence = adapter.buildZangFuEvidence();
      expect(evidence.organMappingStatus, 'MISSING');
      expect(evidence.hasAnsweredEvidence, isFalse);
    });
  });
}
