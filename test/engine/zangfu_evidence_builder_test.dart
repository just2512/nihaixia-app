import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/zangfu_evidence_builder.dart';
import 'package:nihaisha_app/models/zangfu_evidence.dart';

void main() {
  group('脏腑独立证据层', () {

    test('保留跟进问答与用户选择症状的来源，不做脏腑归属', () {
      final assessment = ZangFuEvidenceBuilder.build(
        qAnswers: const {},
        extSymptoms: const {'cough_wheeze'},
        answers: const {
          'treatment_history': '被误下过',
          'combined_treatment_history': '不确定',
          'food_stagnation_answer': '有明确食积表现',
          'sun_taiyin_repeated_purgation_answer': '曾多次使用',
          'sun_taiyin_epigastric_hard': '有心下痞硬',
        },
        selectedSymptoms: const ['头痛', '项背强'],
      );

      final byKey = {
        for (final record in assessment.records) record.questionKey: record,
      };
      expect(byKey['treatment_history']?.answerText, '被误下过');
      expect(byKey['combined_treatment_history']?.state,
          ZangFuEvidenceAnswerState.unknown);
      expect(byKey['food_stagnation']?.answerText, '有明确食积表现');
      expect(byKey['sun_taiyin_repeated_purgation']?.answerText, '曾多次使用');
      expect(byKey['sun_taiyin_epigastric_hard']?.answerText, '有心下痞硬');
      expect(byKey['selected_symptom_1']?.answerText, '头痛');
      expect(byKey['selected_symptom_2']?.answerText, '项背强');
      expect(byKey['selected_symptom_1']?.sourceId, 'selected_symptom:1');
      expect(assessment.unclassifiedAdditionalEvidence, ['cough_wheeze']);
      expect(assessment.organMappingStatus, 'MISSING');
    });

    test('使用 App 稳定问项 key 还原原始选项，不创建脏腑归属', () {
      final assessment = ZangFuEvidenceBuilder.build(
        qAnswers: const {
          kQ1: 1,
          kQ2: 13,
          kQ3: 2,
          kQ8: 2,
        },
        extSymptoms: const {},
      );

      final temperature = assessment.records.firstWhere(
        (record) => record.questionKey == kQ1,
      );
      final pulse = assessment.records.firstWhere(
        (record) => record.questionKey == kQ2,
      );
      final appetite = assessment.records.firstWhere(
        (record) => record.questionKey == kQ8,
      );

      expect(temperature.answerText, contains('手脚温热'));
      expect(temperature.state, ZangFuEvidenceAnswerState.explicitNormal);
      expect(pulse.answerText, contains('不清楚'));
      expect(pulse.state, ZangFuEvidenceAnswerState.unknown);
      expect(appetite.answerText, contains('没有胃口'));
      expect(assessment.organMappingStatus, 'MISSING');
      expect(assessment.hasVerifiedOrganMapping, isFalse);
    });

    test('未作答与非法选项不转为阴性证据', () {
      final assessment = ZangFuEvidenceBuilder.build(
        qAnswers: const {kQ3: 999},
        extSymptoms: const {},
      );

      final unanswered = assessment.records.firstWhere(
        (record) => record.questionKey == kQ1,
      );
      final invalid = assessment.records.firstWhere(
        (record) => record.questionKey == kQ3,
      );

      expect(unanswered.state, ZangFuEvidenceAnswerState.unanswered);
      expect(unanswered.answerText, isNull);
      expect(invalid.state, ZangFuEvidenceAnswerState.invalid);
      expect(invalid.answerText, isNull);
      expect(assessment.hasAnsweredEvidence, isFalse);
    });

    test('脉舌交叉验证追问完整保留原始答案与来源', () {
      const answers = {
        'pulse_cross_drink': '口渴，喜热饮',
        'pulse_cross_urine': '清长色淡',
        'pulse_cross_limbs': '偏冷',
        'pulse_cross_surface': '有发热恶寒',
        'pulse_cross_interior': '腹满或便秘',
        'pulse_cross_shaoyang': '口苦咽干',
        'pulse_cross_taiyin': '食欲差或不渴',
      };
      final assessment = ZangFuEvidenceBuilder.build(
        qAnswers: const {},
        extSymptoms: const {},
        answers: answers,
      );
      final byKey = {
        for (final record in assessment.records) record.questionKey: record,
      };
      for (final item in answers.entries) {
        expect(byKey[item.key]?.answerText, item.value, reason: item.key);
        expect(byKey[item.key]?.sourceId, 'follow_up:' + item.key);
        expect(byKey[item.key]?.state, ZangFuEvidenceAnswerState.answered);
      }
      expect(assessment.organMappingStatus, 'MISSING');
      expect(assessment.hasVerifiedOrganMapping, isFalse);
    });

    test('扩展症状只保留原文，不映射到脏腑', () {
      final assessment = ZangFuEvidenceBuilder.build(
        qAnswers: const {},
        extSymptoms: const {'口苦', '胁肋不适'},
      );

      expect(assessment.unclassifiedAdditionalEvidence, ['口苦', '胁肋不适']);
      expect(assessment.hasVerifiedOrganMapping, isFalse);
    });

    test('舌象、主脉与兼脉作为原始证据独立保留，不生成脏腑归属', () {
      final assessment = ZangFuEvidenceBuilder.build(
        qAnswers: const {},
        extSymptoms: const {},
        tongueCoating: '薄白',
        tongueShape: '淡红',
        pulseType: '浮',
        pulseTypeSecondary: '紧',
      );

      expect(
        assessment.records.map((record) => record.questionKey),
        containsAll([
          'tongue_coating',
          'tongue_shape',
          'pulse_type',
          'pulse_type_secondary',
        ]),
      );
      expect(assessment.records.map((record) => record.answerText),
          containsAll(['薄白', '淡红', '浮', '紧']));
      expect(assessment.organMappingStatus, 'MISSING');
      expect(assessment.hasVerifiedOrganMapping, isFalse);
    });

    test('寒热选择与动态追问保留原始回答、未知状态和来源', () {
      final engine = DiagnosticEngine();
      engine.answerTemperaturePattern('fever_chills');
      const answers = {
        'three_yang_pulse_position': '不清楚',
        'combined_clause36_dyspnea': '没有气喘',
        'combined_clause36_chest_fullness': '不确定',
        'combined_diarrhea_status': '有下利',
        'combined_clause172_diarrhea': '明确有自下利（第172条）',
        'clause146_mild_nausea': '有微呕/恶心（第146条线索）',
        'illness_duration': '约6—7天（第146条）',
        'shaoyang147_treatment_sequence': '先发汗后又误下',
        'nausea': '不想吐',
        'bitter_mouth': '口苦',
        'tidal_fever': '有潮热',
        'food_stagnation': '有明确食积表现',
        'sun_taiyin_repeated_purgation': '曾多次使用',
        'sun_taiyin_epigastric_hard': '有心下痞硬',
        'combined_treatment_history': '明确没有',
      };
      for (final entry in answers.entries) {
        engine.answerFollowUp(entry.key, entry.value);
      }

      final assessment = engine.buildZangFuEvidence();
      final byKey = {
        for (final record in assessment.records) record.questionKey: record,
      };

      expect(byKey['temperature_pattern']?.answerText, '发热 + 怕冷');
      expect(byKey['temperature_pattern']?.sourceId,
          'app_question:temperature_pattern');
      for (final entry in answers.entries) {
        expect(byKey[entry.key]?.answerText, entry.value, reason: entry.key);
        expect(byKey[entry.key]?.sourceId, 'follow_up:${entry.key}');
      }
      expect(byKey['three_yang_pulse_position']?.state,
          ZangFuEvidenceAnswerState.unknown);
      expect(byKey['combined_clause36_chest_fullness']?.state,
          ZangFuEvidenceAnswerState.unknown);
      expect(byKey['nausea']?.state,
          ZangFuEvidenceAnswerState.explicitNormal);
      expect(assessment.organMappingStatus, 'MISSING');
      expect(assessment.hasVerifiedOrganMapping, isFalse);
    });

  });
}
