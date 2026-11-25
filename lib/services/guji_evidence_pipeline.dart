import '../data/guji_data.dart';
import '../models/ai_evidence.dart';

/// Adapts explicitly requested bundled Guji chapters into retrieval candidates.
/// Preserves the existing book order, chapter order and substring matching.
class GujiEvidencePipeline {
  static CandidateEvidenceBatch retrieveCandidates({
    required String requestId,
    required String originalQuery,
    required GujiBook book,
    required List<String> terms,
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
          reasons: const ['EXPLICIT_GUIJI_BOOK_CHAPTER_MATCH'],
        ),
    ];
    final candidates = <CandidateEvidence>[];

    for (final chapter in chapters) {
      final matchedTermIndex = terms.indexWhere(
        (term) => chapter.title.contains(term) || chapter.body.contains(term),
      );
      if (matchedTermIndex < 0) continue;

      final sourceId = 'guji:${book.id}:${chapter.index}';
      final localBacklink = 'guji:${book.id}#chapter:${chapter.index}';
      final isTruncated = chapter.body.length > 1400;
      candidates.add(
        CandidateEvidence(
          evidenceId: '$requestId:$sourceId',
          sourceId: sourceId,
          origin: CandidateEvidenceOrigin.appData,
          materialKind: 'classic_text',
          title: chapter.title,
          chapterPath: '${book.id}#chapter=${chapter.index}',
          excerpt: isTruncated
              ? chapter.body.substring(0, 1400)
              : chapter.body,
          queryId: 'guji-q${matchedTermIndex + 1}',
          retrievalMethod: 'GUIJI_CHAPTER_SUBSTRING_MATCH',
          matchBasis: 'TITLE_OR_BODY_SUBSTRING',
          completeness: isTruncated
              ? CandidateEvidenceCompleteness.truncated
              : CandidateEvidenceCompleteness.complete,
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
          : const ['GUIJI_BOOK_AND_CHAPTER_SEQUENCE_PRESERVED'],
    );
  }
}
