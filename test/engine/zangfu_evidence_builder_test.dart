import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/engine/zangfu_evidence_builder.dart';
import 'package:nihaisha_app/models/zangfu_evidence.dart';

void main() {
  group('脏腑独立证据层', () {
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
  });
}
