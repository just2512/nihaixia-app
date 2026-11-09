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


    void addRawEvidence(
      String key,
      String label,
      String? value, {
      String sourcePrefix = 'tongue_pulse',
    }) {
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
        sourceId: '$sourcePrefix:$key',
      ));
    }

    addRawEvidence('tongue_coating', '舌苔', tongueCoating);
    addRawEvidence('tongue_shape', '舌形', tongueShape);
    addRawEvidence('pulse_type', '主脉', pulseType);
    addRawEvidence('pulse_type_secondary', '兼脉', pulseTypeSecondary);

    final temperatureKey = answers['temperature'];
    if (temperatureKey is String && temperatureKey.isNotEmpty) {
      final matchingTemperature = DiagnosticRules.temperaturePatterns.where(
        (option) => option.key == temperatureKey,
      );
      addRawEvidence(
        'temperature_pattern',
        '寒热辨经',
        matchingTemperature.isEmpty
            ? temperatureKey
            : matchingTemperature.first.label,
        sourcePrefix: 'app_question',
      );
    }

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
      const FollowUpQuestion(
        key: 'three_yang_pulse_position',
        question: '【核对第268条】是否已由专业人员确认脉浮大、上关上？',
        options: ['已由专业人员确认', '未确认', '不清楚'],
      ),
      const FollowUpQuestion(
        key: 'combined_clause36_dyspnea',
        question: '【核对第36条】是否明确有气喘？',
        options: ['明确气喘（第36条）', '没有气喘', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'combined_clause36_chest_fullness',
        question: '【核对第36条】喘的同时是否明确有胸满？',
        options: ['有胸满（第36条）', '没有胸满', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'combined_diarrhea_status',
        question: '【核对第33条】本次是否明确没有下利？',
        options: ['明确没有下利（第33条）', '有下利', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'combined_clause172_diarrhea',
        question: '【核对第172条】本次是否明确有自下利？',
        options: ['明确有自下利（第172条）', '没有下利', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'clause146_mild_nausea',
        question: '【核对第146条】是否有微呕或恶心？',
        options: ['有微呕/恶心（第146条线索）', '没有', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'illness_duration',
        question: '【核对第146、147条】本次伤寒发病约几天？',
        options: ['约6—7天（第146条）', '约5—6天（第147条）', '不足5天', '超过7天', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'shaoyang147_treatment_sequence',
        question: '【核对第147条】此前是否先发汗后又误用攻下法？',
        options: ['先发汗后又误下', '只发汗', '只误下', '没有', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'nausea',
        question: '【核对第147条】是否“渴而不呕”？',
        options: ['不想吐', '有微呕/恶心', '呕吐明显', '不确定'],
      ),
      // Preserve cross-validation answers as raw, attributable evidence.
      // These prompts are generated by DiagnosticEngine rather than the
      // static DiagnosticRules follow-up collections above.
      const FollowUpQuestion(
        key: 'pulse_cross_drink',
        question: '口渴与饮水偏好如何？',
        options: ['不渴', '口渴，喜热饮', '口渴，喜冷饮', '口干但不想喝', '不确定'],
      ),
      const FollowUpQuestion(
        key: 'pulse_cross_urine',
        question: '小便颜色和排尿情况如何？',
        options: ['清长色淡', '短赤色深', '排尿不利', '正常', '不清楚'],
      ),
      const FollowUpQuestion(
        key: 'pulse_cross_limbs',
        question: '手足温度如何？',
        options: ['温热', '偏冷', '冷热不均', '不清楚'],
      ),
      const FollowUpQuestion(
        key: 'pulse_cross_surface',
        question: '是否有发热恶寒、头痛或项背强等表证线索？',
        options: ['有发热恶寒', '有头痛或项背强', '都没有', '不清楚'],
      ),
      const FollowUpQuestion(
        key: 'pulse_cross_interior',
        question: '腹部与大便情况如何？',
        options: ['腹满或便秘', '腹痛喜按或便溏下利', '腹痛拒按', '没有明显异常', '不清楚'],
      ),
      const FollowUpQuestion(
        key: 'pulse_cross_shaoyang',
        question: '是否有少阳相关问诊线索？',
        options: ['口苦咽干', '往来寒热', '两者都有', '都没有', '不清楚'],
      ),
      const FollowUpQuestion(
        key: 'pulse_cross_taiyin',
        question: '是否有太阴相关问诊线索？',
        options: ['下利或腹痛喜按', '食欲差或不渴', '两类都有', '都没有', '不清楚'],
      ),
    ];
    final recordedFollowUpKeys = <String>{};
    for (final question in followUpQuestions) {
      if (mainQuestionKeys.contains(question.key) ||
          !recordedFollowUpKeys.add(question.key)) {
        continue;
      }
      final preservedRawAnswer = answers['raw_followup:${question.key}'];
      final rawAnswer = preservedRawAnswer ?? switch (question.key) {
        'food_stagnation' => answers['food_stagnation_answer'],
        'sun_taiyin_repeated_purgation' =>
          answers['sun_taiyin_repeated_purgation_answer'],
        'nausea' => answers['nausea_answer'],
        'bitter_mouth' => answers['bitter_mouth_answer'],
        'tidal_fever' => answers['tidal_fever_answer'],
        'clause146_mild_nausea' =>
          answers['clause146_mild_nausea_answer'],
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
      value == '不想吐' ||
      value == '不恶心' ||
      value == '没有呕吐' ||
      value == '都没有' ||
      value == '没有此症状';
}
