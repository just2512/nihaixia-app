import '../engine/diagnostic_rules.dart';
import '../models/zangfu_evidence.dart';

/// 将 App 自己的稳定问项 key / 选项序号还原为原始问答记录。
/// 不复用上游按数组下标的脏腑标签，不进行脏腑映射或诊断。
class ZangFuEvidenceBuilder {
  static ZangFuEvidenceAssessment build({
    required Map<String, int> qAnswers,
    required Set<String> extSymptoms,
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
