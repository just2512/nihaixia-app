import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/classic_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('稳定来源 ID 可以精确反查原始索引条目', () async {
    final result = await ClassicSearchService.search('太阳');
    expect(result.hits, isNotEmpty);

    final original = result.hits.first;
    final resolved =
        await ClassicSearchService.findBySourceId(original.sourceId);

    expect(resolved, isNotNull);
    expect(resolved!.sourceId, original.sourceId);
    expect(resolved.title, original.title);
    expect(resolved.localBacklink, original.localBacklink);
  });

  test('未知或 MISSING 来源 ID 不回退到模糊检索', () async {
    expect(await ClassicSearchService.findBySourceId('MISSING'), isNull);
    expect(await ClassicSearchService.findBySourceId(''), isNull);
    expect(
      await ClassicSearchService.findBySourceId('unknown:invented:source'),
      isNull,
    );
  });

  test('同一索引条目重复检索生成稳定来源 ID', () async {
    final first = await ClassicSearchService.search('太阳');
    final second = await ClassicSearchService.search('太阳');
    expect(first.hits, isNotEmpty);
    expect(second.hits, isNotEmpty);
    expect(second.hits.first.sourceId, first.hits.first.sourceId);
  });

  test('source identity does not change when a display title changes', () {
    const original = ClassicHit(
      source: 'shanghan',
      sourceLabel: '伤寒论讲稿',
      title: '旧标题',
      asset: 'assets/shanghan/clause_001.md',
      snippet: '片段',
    );
    const renamed = ClassicHit(
      source: 'shanghan',
      sourceLabel: '伤寒论讲稿',
      title: '新标题',
      asset: 'assets/shanghan/clause_001.md',
      snippet: '片段',
    );

    expect(original.sourceId, 'shanghan:assets/shanghan/clause_001.md');
    expect(renamed.sourceId, original.sourceId);
  });

  test('book chapter identity does not include the display title', () {
    const firstTitle = ClassicHit(
      source: 'guji',
      sourceLabel: '伤寒论',
      title: '旧章节名',
      bookId: 'shanghan_lun',
      chapterIndex: 1,
      snippet: '片段',
    );
    const revisedTitle = ClassicHit(
      source: 'guji',
      sourceLabel: '伤寒论',
      title: '修订后的章节名',
      bookId: 'shanghan_lun',
      chapterIndex: 1,
      snippet: '片段',
    );

    expect(firstTitle.sourceId, 'guji:shanghan_lun:1');
    expect(revisedTitle.sourceId, firstTitle.sourceId);
  });

  test('legacy title-bearing source IDs still resolve by stable asset key', () async {
    final result = await ClassicSearchService.search('太阳');
    expect(result.hits, isNotEmpty);
    final original = result.hits.first;
    final legacyId = [
      original.source,
      original.asset ?? original.bookId ?? 'MISSING',
      original.chapterIndex?.toString() ?? 'MISSING',
      original.title,
    ].join(':');

    final resolved = await ClassicSearchService.findBySourceId(legacyId);

    expect(resolved, isNotNull);
    expect(resolved!.sourceId, original.sourceId);
    expect(resolved.localBacklink, original.localBacklink);
  });

  test('entries without a stable local key do not use title as identity', () {
    const unbacked = ClassicHit(
      source: 'unknown',
      sourceLabel: '未知来源',
      title: '仅有标题',
      snippet: '片段',
    );

    expect(unbacked.sourceId, 'MISSING');
  });

}
