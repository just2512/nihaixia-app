/// Runtime retrieval DTOs for the five-layer AI pipeline.
/// Candidates carry the App-local entry identity and retrieved learning content.

enum CandidateEvidenceBatchStatus {
  retrieved,
  missing,
  failed,
  unknown,
  partial,
}

enum CandidateEvidenceOrigin {
  system,
  user,
  appData,
  unknown,
}

enum CandidateEvidenceCompleteness {
  complete,
  truncated,
  unknown,
}

class DerivedEvidenceQuery {
  DerivedEvidenceQuery({
    required this.queryId,
    required this.query,
    required List<String> reasons,
  }) : reasons = List.unmodifiable(reasons);

  final String queryId;
  final String query;
  final List<String> reasons;

  DerivedEvidenceQuery copyWith({String? queryId}) => DerivedEvidenceQuery(
        queryId: queryId ?? this.queryId,
        query: query,
        reasons: reasons,
      );
}

/// One retrieved candidate, before any evidence-ranking decision.
///
/// [sourceId] is the source resolver's existing stable ID. It may be the
/// explicit MISSING sentinel when the index row has no resolvable locator;
/// [evidenceId] is the unique identity of this candidate in [requestId].
class CandidateEvidence {
  const CandidateEvidence({
    required this.evidenceId,
    required this.sourceId,
    required this.origin,
    required this.materialKind,
    required this.title,
    required this.locator,
    required this.excerpt,
    required this.queryId,
    required this.retrievalMethod,
    required this.matchBasis,
    required this.completeness,
    required this.sourceKey,
    required this.sourceLabel,
    required this.localBacklink,
    required this.hasLocalBacklink,
    this.assetId,
    this.bookId,
    this.chapterIndex,
    this.chunkId,
    this.chapterPath,
  });

  final String evidenceId;
  final String sourceId;
  final CandidateEvidenceOrigin origin;
  final String materialKind;
  final String? assetId;
  final String? chunkId;
  final String title;
  final String? chapterPath;
  final String locator;
  final String excerpt;
  final String queryId;
  final String retrievalMethod;
  final String matchBasis;
  final CandidateEvidenceCompleteness completeness;

  // Local presentation metadata used by the knowledge-context materializer.
  final String sourceKey;
  final String sourceLabel;
  final String localBacklink;
  final bool hasLocalBacklink;
  final String? bookId;
  final int? chapterIndex;

  // Compatibility getters keep the existing classic context formatter
  // unchanged while the DTO boundary is introduced.
  String? get asset => assetId;
  String get snippet => excerpt;
  String get source => sourceKey;

  /// Copies a candidate into a combined request namespace without changing
  /// its stable source ID or retrieved content.
  CandidateEvidence copyWith({
    String? evidenceId,
    String? queryId,
  }) =>
      CandidateEvidence(
        evidenceId: evidenceId ?? this.evidenceId,
        sourceId: sourceId,
        origin: origin,
        materialKind: materialKind,
        title: title,
        excerpt: excerpt,
        queryId: queryId ?? this.queryId,
        retrievalMethod: retrievalMethod,
        matchBasis: matchBasis,
        completeness: completeness,
        sourceKey: sourceKey,
        sourceLabel: sourceLabel,
        localBacklink: localBacklink,
        hasLocalBacklink: hasLocalBacklink,
        assetId: assetId,
        bookId: bookId,
        chapterIndex: chapterIndex,
        chunkId: chunkId,
        chapterPath: chapterPath,
      );
}

class CandidateEvidenceBatch {
  CandidateEvidenceBatch({
    required this.requestId,
    required this.originalQuery,
    required List<DerivedEvidenceQuery> derivedQueries,
    required this.status,
    required List<CandidateEvidence> candidates,
    required List<String> diagnostics,
  })  : derivedQueries = List.unmodifiable(derivedQueries),
        candidates = List.unmodifiable(candidates),
        diagnostics = List.unmodifiable(diagnostics);

  final String requestId;
  final String originalQuery;
  final List<DerivedEvidenceQuery> derivedQueries;
  final CandidateEvidenceBatchStatus status;
  final List<CandidateEvidence> candidates;
  final List<String> diagnostics;
}
