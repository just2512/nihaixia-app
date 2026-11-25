import '../data/guji_data.dart';
import '../models/ai_evidence.dart';

/// Builds source-bound candidates from the app's parsed Guji chapter assets.
///
/// The stable source ID is app-local. No bibliographic volume/page or external
/// source verification is inferred from an asset path or chapter index.
class GujiEvidencePipeline {
  static CandidateEvidenceBatch retrieveCandidates({
    required String requestId,
    required String originalQuery,
    required List<String> terms,
    required GujiBook book,
    required List<GujiChapter> chapters,
  }) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }
    final derivedQueries = [
      for (var index = 0; index < terms.length; index++)
        DerivedEvidenceQuery(
          queryId: 'guji-q${index + 1}',
          query: terms[index],
          reasons: const ['LEGACY_GUIJI_CHAPTER_SUBSTRING_MATCH'],
        ),
    ];
    final candidates = <CandidateEvidence>[];
    for (final chapter in chapters) {
      final matchedTermIndex = terms.indexWhere(
        (term) =>
            chapter.title.contains(term) || chapter.body.contains(term),
      );
      if (matchedTermIndex < 0) continue;
      final sourceId = 'guji:${book.id}:${chapter.index}';
      final localBacklink = 'guji:${book.id}#chapter:${chapter.index}';
      candidates.add(
        CandidateEvidence(
          evidenceId: '$requestId:$sourceId',
          sourceId: sourceId,
          sourceVersion: 'UNKNOWN',
          origin: CandidateEvidenceOrigin.appData,
          materialKind: 'classic_text',
          verificationStatus: 'UNKNOWN',
          assetId: book.asset,
          chunkId: '${book.id}:${chapter.index}',
          title: chapter.title,
          chapterPath: localBacklink,
          locator: '${book.asset}#chapter=${chapter.title}',
          locatorStatus: 'MISSING',
          excerpt: chapter.body,
          queryId: 'guji-q${matchedTermIndex + 1}',
          retrievalMethod: 'GUIJI_ASSET_CHAPTER_SUBSTRING',
          matchBasis: 'CHAPTER_TITLE_OR_BODY_CONTAINS_TERM',
          completeness: CandidateEvidenceCompleteness.unknown,
          sourceKey: 'guji',
          sourceLabel: book.title,
          localBacklink: localBacklink,
          hasLocalBacklink: true,
          bookId: book.id,
          chapterIndex: chapter.index,
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
          ? const ['GUIJI_CHAPTER_NO_MATCH']
          : const ['GUIJI_CHAPTER_ASSET_SEQUENCE_PRESERVED'],
    );
  }
}
