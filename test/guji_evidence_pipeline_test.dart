import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/guji_data.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/models/evidence_ranking_decision.dart';
import 'package:nihaisha_app/services/guji_evidence_pipeline.dart';
import 'package:nihaisha_app/services/legacy_order_evidence_ranker.dart';

const _lingshu = GujiBook(
  id: 'lingshu',
  title: '黄帝内经·灵枢',
  author: '佚名 · 托名黄帝',
  asset: 'assets/guji/lingshu.txt',
  intro: '测试书目',
  chapterCount: 82,
);

void main() {
  test('emits unique source-bound candidates in original chapter order', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'request-1:guji:lingshu',
      originalQuery: '经络 针刺',
      terms: const ['经络', '针刺', '阴阳'],
      book: _lingshu,
      chapters: const [
        GujiChapter(index: 4, title: '经络论', body: '针刺经络以和阴阳。'),
        GujiChapter(index: 8, title: '阴阳别论', body: '阴阳之气行于脏腑。'),
        GujiChapter(index: 11, title: '脉度', body: '脉度与经络相应。'),
        GujiChapter(index: 15, title: '无关篇章', body: '无命中内容。'),
      ],
    );
    expect(batch.status, CandidateEvidenceBatchStatus.retrieved);
    expect(batch.candidates.map((item) => item.sourceId).toList(), [
      'guji:lingshu:4',
      'guji:lingshu:8',
      'guji:lingshu:11',
    ]);
    expect(batch.candidates.map((item) => item.queryId).toList(), [
      'guji-q1',
      'guji-q2',
      'guji-q1',
    ]);
    expect(batch.candidates.map((item) => item.evidenceId).toSet(), hasLength(3));
    expect(batch.candidates.every((item) =>
        item.origin == CandidateEvidenceOrigin.appData), isTrue);
    expect(batch.candidates.every((item) => item.sourceVersion == 'UNKNOWN'), isTrue);
    expect(batch.candidates.every((item) => item.verificationStatus == 'UNKNOWN'), isTrue);
    expect(batch.candidates.every((item) => item.locatorStatus == 'MISSING'), isTrue);
    expect(batch.candidates.first.localBacklink, 'guji:lingshu#chapter:4');
    expect(batch.candidates.first.locator, 'assets/guji/lingshu.txt#chapter=经络论');
    expect(batch.candidates.first.bookId, 'lingshu');
    expect(batch.candidates.first.chapterIndex, 4);
  });

  test('selection records the existing two-chapter per-book limit', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'request-2:guji:lingshu',
      originalQuery: '经络',
      terms: const ['经络'],
      book: _lingshu,
      chapters: const [
        GujiChapter(index: 0, title: '第一篇', body: '经络第一'),
        GujiChapter(index: 1, title: '第二篇', body: '经络第二'),
        GujiChapter(index: 2, title: '第三篇', body: '经络第三'),
      ],
    );
    final ranked = LegacyOrderEvidenceRanker.rank(
      batch.candidates,
      requestId: batch.requestId,
      maxKeptEvidence: 2,
      keepReasonCode: 'LEGACY_GUIJI_CHAPTER_ORDER_WITHIN_BOOK_LIMIT',
      keepReason: 'Preserved original chapter order.',
      dropReasonCode: 'LEGACY_GUIJI_TWO_CHAPTER_PER_BOOK_LIMIT',
      dropReason: 'Excluded by the existing two-chapter per-book limit.',
    );
    expect(ranked.orderedEvidenceIds,
        batch.candidates.take(2).map((item) => item.evidenceId).toList());
    expect(ranked.decisions.map((item) => item.disposition).toList(), [
      EvidenceDecisionDisposition.keep,
      EvidenceDecisionDisposition.keep,
      EvidenceDecisionDisposition.drop,
    ]);
    expect(ranked.decisions.last.reasonCode, 'LEGACY_GUIJI_TWO_CHAPTER_PER_BOOK_LIMIT');
    expect(ranked.budget.unit, EvidenceBudgetUnit.unknown);
    expect(ranked.budget.applied, isFalse);
    expect(ranked.budget.limit, isNull);
  });

  test('uses the first matching query term and does not duplicate a chapter', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'request-3:guji:lingshu',
      originalQuery: '经络 阴阳',
      terms: const ['经络', '阴阳'],
      book: _lingshu,
      chapters: const [
        GujiChapter(index: 2, title: '经络与阴阳', body: '经络，阴阳。'),
      ],
    );
    expect(batch.candidates, hasLength(1));
    expect(batch.candidates.single.queryId, 'guji-q1');
  });

  test('returns MISSING when no chapter matches and rejects empty request ID', () {
    final batch = GujiEvidencePipeline.retrieveCandidates(
      requestId: 'request-4:guji:lingshu',
      originalQuery: '未命中',
      terms: const ['未命中'],
      book: _lingshu,
      chapters: const [
        GujiChapter(index: 1, title: '经络', body: '相关古文。'),
      ],
    );
    expect(batch.status, CandidateEvidenceBatchStatus.missing);
    expect(batch.candidates, isEmpty);
    expect(batch.diagnostics, contains('GUIJI_CHAPTER_NO_MATCH'));
    expect(() => GujiEvidencePipeline.retrieveCandidates(
      requestId: ' ',
      originalQuery: '经络',
      terms: const ['经络'],
      book: _lingshu,
      chapters: const [],
    ), throwsArgumentError);
  });
}
