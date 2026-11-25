import '../data/medical_case_data.dart';
import '../models/ai_evidence.dart';

/// Builds auditable candidates for the existing App-local medical-case search.
///
/// This adapter preserves the old source-list order and first matching query
/// term. It does not rank clinical correctness or promote the internal case
/// sequence into an original bibliographic locator.
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
          reasons: const ['LEGACY_MEDICAL_CASE_MATCH_TERM'],
        ),
    ];
    final candidates = <CandidateEvidence>[];

    // The historical path scanned cases first, then accepted a case once when
    // any term matched. Keep that order and record the first matching term.
    for (final medicalCase in cases) {
      final matchedTermIndex =
          terms.indexWhere(medicalCase.matches);
      if (matchedTermIndex < 0) continue;

      final sourceId = 'medical_case:${medicalCase.seq}';
      final localBacklink =
          'medical_case:internal-seq:${medicalCase.seq}';
      final ledger = medicalCase.sourceLedger;
      final rawExcerpt = ledger.originalExcerpt.trim();
      candidates.add(
        CandidateEvidence(
          evidenceId: '$requestId:$sourceId',
          sourceId: sourceId,
          sourceVersion: 'UNKNOWN',
          origin: CandidateEvidenceOrigin.appData,
          materialKind: 'medical_case',
          verificationStatus: ledger.sourceStatus,
          title: medicalCase.displayName,
          locator: localBacklink,
          locatorStatus: ledger.status,
          excerpt: rawExcerpt == 'MISSING' ? '' : rawExcerpt,
          queryId: 'medical-q${matchedTermIndex + 1}',
          retrievalMethod: 'MEDICAL_CASE_NORMALIZED_TEXT_MATCH',
          matchBasis: 'NORMALIZED_CASE_FIELD_SUBSTRING',
          completeness: CandidateEvidenceCompleteness.unknown,
          sourceKey: 'medical_case',
          sourceLabel: 'App 医案库',
          localBacklink: localBacklink,
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
          : const ['MEDICAL_CASE_SOURCE_SEQUENCE_PRESERVED'],
    );
  }
}
