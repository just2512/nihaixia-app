import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/guji_data.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/models/evidence_ranking_decision.dart';
import 'package:nihaisha_app/services/guji_evidence_pipeline.dart';
import 'package:nihaisha_app/services/legacy_order_evidence_ranker.dart';

void main() {
  const book = GujiBook(
    id: 'lingshu-test',
    title: '测试古籍',
    author: '佚名',
    asset: 'assets/guji/test.txt',
    intro: 'test',
    chapterCount: 4,
  );

  test('preserves book chapter order and records the first matching query', () {
    final chapters = [
      const GujiChapter(
        index: 8,
        title: '经脉甲篇',
        body: '经络与针法原文。',
      ),
      const GujiChapter(
        index: 2,
        title: '乙篇',
        body: '灵枢所载经脉原文。',
      ),
      const GujiChapter(
        index: 5,
        title: '针法丙篇',
        body: '针法原文。',
      ),
      const GujiChapter(
        index: 9,
        title: '无关篇',
        body: '与查询无关。',
      ),
    ];

    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'guji-request-1',
      originalQuery: '灵枢经络针法',
      book: book,
      terms: const ['灵枢经络针法', '灵枢', '经络', '针法'],
      chapters: chapters,
    );

    expect(batch.status, CandidateEvidenceBatchStatus.retrieved);
    expect(batch.candidates.map((item) => item.chapterIndex), [8, 2, 5]);
    expect(batch.candidates.map((item) => item.sourceId), [
      'guji:lingshu-test:8',
      'guji:lingshu-test:2',
      'guji:lingshu-test:5',
    ]);
    expect(batch.candidates.first.queryId, 'guji-q3');
    expect(batch.candidates[1].queryId, 'guji-q2');
    expect(
      batch.diagnostics,
      contains('GUIJI_BOOK_AND_CHAPTER_SEQUENCE_PRESERVED'),
    );
  });

  test('keeps the legacy two chapter limit explicit with KEEP and DROP reasons', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'guji-request-2',
      originalQuery: '灵枢',
      book: book,
      terms: const ['灵枢'],
      chapters: const [
        GujiChapter(index: 0, title: '篇一', body: '灵枢正文一'),
        GujiChapter(index: 1, title: '篇二', body: '灵枢正文二'),
        GujiChapter(index: 2, title: '篇三', body: '灵枢正文三'),
      ],
    );

    final ranked = LegacyOrderEvidenceRanker.rank(
      batch.candidates,
      requestId: batch.requestId,
      maxKeptEvidence: 2,
      keepReasonCode: 'LEGACY_GUIJI_CHAPTER_SEQUENCE_WITHIN_BOOK',
      keepReason: 'Preserved chapter sequence.',
      dropReasonCode: 'LEGACY_GUIJI_TWO_CHAPTER_LIMIT',
      dropReason: 'Excluded by the existing two-chapter per-book limit.',
    );

    expect(ranked.orderedEvidenceIds, [
      batch.candidates[0].evidenceId,
      batch.candidates[1].evidenceId,
    ]);
    expect(ranked.decisions.map((item) => item.disposition), [
      EvidenceDecisionDisposition.keep,
      EvidenceDecisionDisposition.keep,
      EvidenceDecisionDisposition.drop,
    ]);
    expect(ranked.decisions.last.reasonCode, 'LEGACY_GUIJI_TWO_CHAPTER_LIMIT');
    expect(ranked.decisions.last.orderIndex, isNull);
  });

  test('keeps internal navigation separate from bibliographic verification', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'guji-request-3',
      originalQuery: '灵枢',
      book: book,
      terms: const ['灵枢'],
      chapters: const [
        GujiChapter(index: 14, title: '经脉篇', body: '灵枢正文'),
      ],
    );
    final candidate = batch.candidates.single;

    expect(candidate.sourceId, 'guji:lingshu-test:14');
    expect(candidate.localBacklink, 'guji:lingshu-test#chapter:14');
    expect(candidate.locatorStatus, 'PARTIAL');
    expect(candidate.verificationStatus, 'UNKNOWN');
    expect(candidate.sourceVersion, 'UNKNOWN');
    expect(candidate.origin, CandidateEvidenceOrigin.appData);
    expect(candidate.hasLocalBacklink, isTrue);
  });

  test('marks excerpts as truncated without changing the source status', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'guji-request-4',
      originalQuery: '灵枢',
      book: book,
      terms: const ['灵枢'],
      chapters: [
        GujiChapter(
          index: 1,
          title: '经脉篇',
          body: '灵枢' + List<String>.filled(1500, '经').join(),
        ),
      ],
    );
    final candidate = batch.candidates.single;

    expect(candidate.excerpt.length, 1400);
    expect(candidate.completeness, CandidateEvidenceCompleteness.truncated);
    expect(candidate.verificationStatus, 'UNKNOWN');
    expect(candidate.locatorStatus, 'PARTIAL');
  });

  test('returns MISSING for no matches and does not invent candidates', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'guji-request-5',
      originalQuery: '无关问题',
      book: book,
      terms: const ['无关问题'],
      chapters: const [
        GujiChapter(index: 0, title: '经脉篇', body: '古籍正文'),
      ],
    );

    expect(batch.status, CandidateEvidenceBatchStatus.missing);
    expect(batch.candidates, isEmpty);
    expect(batch.diagnostics, ['GUIJI_CHAPTER_NO_MATCH']);
  });
}
