import '../engine/diagnostic_rules.dart';
import '../models/zangfu_evidence.dart';

/// 将 App 自己的稳定问项 key / 选项序号还原为原始问答记录。
/// 不复用上游按数组下标的脏腑标签，不进行脏腑映射或诊断。
class ZangFuEvidenceBuilder {
  static ZangFuEvidenceAssessment build({
    required Map<String, int> qAnswers,
    required Set<String> extSymptoms,
    Map<String, dynamic> answers = const {},
    List<String> selectedSymptoms = const [],
    String? tongueCoating,
    String? tongueShape,
    String? pulseType,
    String? pulseTypeSecondary,
  }) {
    final questions = [
      ...DiagnosticRules.tenQuestions,
      DiagnosticRules.vomitTypeQuestion,
    ];
    final records = <ZangFuEvidenceRecord>[];

    for (final question in questions) {
      final index = qAnswers[question.key];
      if (index == null) {
        records.add(ZangFuEvidenceRecord(
          questionKey: question.key,
          questionLabel: question.question,
          optionIndex: null,
          answerText: null,
          state: ZangFuEvidenceAnswerState.unanswered,
          sourceId: 'app_question:${question.key}',
        ));
        continue;
      }

      if (index < 1 || index > question.options.length) {
        records.add(ZangFuEvidenceRecord(
          questionKey: question.key,
          questionLabel: question.question,
          optionIndex: index,
          answerText: null,
          state: ZangFuEvidenceAnswerState.invalid,
          sourceId: 'app_question:${question.key}',
        ));
        continue;
      }

      final answer = question.options[index - 1];
      final normalized = answer.trim();
      final state = _isUnknown(normalized)
          ? ZangFuEvidenceAnswerState.unknown
          : _isExplicitNormal(normalized)
              ? ZangFuEvidenceAnswerState.explicitNormal
              : ZangFuEvidenceAnswerState.answered;
      records.add(ZangFuEvidenceRecord(
        questionKey: question.key,
        questionLabel: question.question,
        optionIndex: index,
        answerText: normalized,
        state: state,
        sourceId: 'app_question:${question.key}',
      ));
    }


    void addRawEvidence(String key, String label, String? value) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return;
      records.add(ZangFuEvidenceRecord(
        questionKey: key,
        questionLabel: label,
        optionIndex: null,
        answerText: normalized,
        state: _isUnknown(normalized)
            ? ZangFuEvidenceAnswerState.unknown
            : ZangFuEvidenceAnswerState.answered,
        sourceId: 'tongue_pulse:$key',
      ));
    }

    addRawEvidence('tongue_coating', '舌苔', tongueCoating);
    addRawEvidence('tongue_shape', '舌形', tongueShape);
    addRawEvidence('pulse_type', '主脉', pulseType);
    addRawEvidence('pulse_type_secondary', '兼脉', pulseTypeSecondary);

    final mainQuestionKeys =
        DiagnosticRules.tenQuestions.map((question) => question.key).toSet();
    final followUpQuestions = <FollowUpQuestion>[
      for (final questions in DiagnosticRules.followUpQuestions.values)
        ...questions,
      for (final questions in DiagnosticRules.meridianSupplementFollowUps.values)
        ...questions,
      const FollowUpQuestion(
        key: 'food_stagnation',
        question: '是否有明确食积表现？',
        options: ['有明确食积表现', '没有', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'combined_treatment_history',
        question: '本次下利之前，是否曾被误用泻下药或攻下法？',
        options: ['明确没有', '曾经被误用泻下法', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'sun_taiyin_repeated_purgation',
        question: '此前是否曾多次使用泻下药或攻下法？',
        options: ['曾多次使用', '没有', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'sun_taiyin_epigastric_hard',
        question: '是否明确有心下痞硬？',
        options: ['有心下痞硬', '没有', '不确定'],
      ),
    ];
    final recordedFollowUpKeys = <String>{};
    for (final question in followUpQuestions) {
      if (mainQuestionKeys.contains(question.key) ||
          !recordedFollowUpKeys.add(question.key)) {
        continue;
      }
      final rawAnswer = switch (question.key) {
        'food_stagnation' => answers['food_stagnation_answer'],
        'sun_taiyin_repeated_purgation' =>
          answers['sun_taiyin_repeated_purgation_answer'],
        _ => answers[question.key],
      };
      if (rawAnswer is! String || rawAnswer.trim().isEmpty) continue;
      final normalized = rawAnswer.trim();
      final optionIndex = question.options.indexOf(normalized);
      final state = _isUnknown(normalized)
          ? ZangFuEvidenceAnswerState.unknown
          : _isExplicitNormal(normalized)
              ? ZangFuEvidenceAnswerState.explicitNormal
              : ZangFuEvidenceAnswerState.answered;
      records.add(ZangFuEvidenceRecord(
        questionKey: question.key,
        questionLabel: question.question,
        optionIndex: optionIndex < 0 ? null : optionIndex + 1,
        answerText: normalized,
        state: state,
        sourceId: 'follow_up:${question.key}',
      ));
    }

    for (var index = 0; index < selectedSymptoms.length; index++) {
      final symptom = selectedSymptoms[index].trim();
      if (symptom.isEmpty) continue;
      records.add(ZangFuEvidenceRecord(
        questionKey: 'selected_symptom_${index + 1}',
        questionLabel: '用户选择的症状',
        optionIndex: null,
        answerText: symptom,
        state: ZangFuEvidenceAnswerState.answered,
        sourceId: 'selected_symptom:${index + 1}',
      ));
    }

    return ZangFuEvidenceAssessment(
      records: List.unmodifiable(records),
      unclassifiedAdditionalEvidence: List.unmodifiable(
        extSymptoms.toList()..sort(),
      ),
      organMappingStatus: 'MISSING',
    );
  }

  static bool _isUnknown(String value) =>
      value.contains('不清楚') ||
      value.contains('没摸过') ||
      value.contains('不确定');

  static bool _isExplicitNormal(String value) =>
      value.contains('正常') ||
      value == '不痛' ||
      value == '不渴' ||
      value == '都没有' ||
      value == '没有此症状';
}
