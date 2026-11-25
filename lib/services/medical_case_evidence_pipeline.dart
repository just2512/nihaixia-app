import '../data/medical_case_data.dart';
import '../models/ai_evidence.dart';

/// Builds AI retrieval candidates from the App's local medical-case records.
/// Keeps the established case order and first matching query term.
class MedicalCaseEvidencePipeline {
  static CandidateEvidenceBatch retrieveCandidates({
    required String requestId,
    required String originalQuery,
    required List<String> terms,
    required List<MedicalCase> cases,
  }) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }

    final derivedQueries = [
      for (var index = 0; index < terms.length; index++)
        DerivedEvidenceQuery(
          queryId: 'medical-q${index + 1}',
          query: terms[index],
          reasons: const ['MEDICAL_CASE_MATCH_TERM'],
        ),
    ];
    final candidates = <CandidateEvidence>[];

    for (final medicalCase in cases) {
      final matchedTermIndex = terms.indexWhere(medicalCase.matches);
      if (matchedTermIndex < 0) continue;

      final sourceId = 'medical_case:${medicalCase.seq}';
      final excerpt = [
        if (medicalCase.date.isNotEmpty) '日期：${medicalCase.date}',
        if (medicalCase.patient.isNotEmpty) '患者：${medicalCase.patient}',
        if (medicalCase.diagnosis.isNotEmpty) '诊断：${medicalCase.diagnosis}',
        if (medicalCase.mechanism.isNotEmpty) '病机：${medicalCase.mechanism}',
        if (medicalCase.western.isNotEmpty) '西医背景：${medicalCase.western}',
        if (medicalCase.formula.isNotEmpty) '方剂：${medicalCase.formula}',
        if (medicalCase.acupuncture.isNotEmpty) '针灸：${medicalCase.acupuncture}',
        if (medicalCase.method.isNotEmpty) '治法：${medicalCase.method}',
        if (medicalCase.result.isNotEmpty) '记录结果：${medicalCase.result}',
        if (medicalCase.advice.isNotEmpty) '医嘱：${medicalCase.advice}',
        if (medicalCase.view.isNotEmpty) '观点：${medicalCase.view}',
      ].join('\n');

      candidates.add(
        CandidateEvidence(
          evidenceId: '$requestId:$sourceId',
          sourceId: sourceId,
          sourceVersion: 'UNKNOWN',
          origin: CandidateEvidenceOrigin.appData,
          materialKind: 'medical_case',
          verificationStatus: 'NOT_ASSESSED',
          title: medicalCase.displayName,
          locator: sourceId,
          locatorStatus: 'LOCAL_ENTRY',
          excerpt: excerpt,
          queryId: 'medical-q${matchedTermIndex + 1}',
          retrievalMethod: 'MEDICAL_CASE_NORMALIZED_TEXT_MATCH',
          matchBasis: 'NORMALIZED_CASE_FIELD_SUBSTRING',
          completeness: CandidateEvidenceCompleteness.unknown,
          sourceKey: 'medical_case',
          sourceLabel: 'App 医案库',
          localBacklink: sourceId,
          hasLocalBacklink: true,
        ),
      );
    }

    return CandidateEvidenceBatch(
      requestId: requestId,
      originalQuery: originalQuery,
      derivedQueries: derivedQueries,
      status: candidates.isEmpty
          ? CandidateEvidenceBatchStatus.missing
          : CandidateEvidenceBatchStatus.retrieved,
      candidates: candidates,
      diagnostics: candidates.isEmpty
          ? const ['MEDICAL_CASE_NO_MATCH']
          : const ['MEDICAL_CASE_ORDER_PRESERVED'],
    );
  }
}
