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

  test('本草讲稿 sourceId 可精确反查原始资产', () async {
    final result = await ClassicSearchService.search('丹砂');
    final original = result.hits.firstWhere(
      (hit) =>
          hit.source == 'bencao' &&
          (hit.asset ?? '').startsWith('assets/bencao_lecture/'),
    );
    final resolved =
        await ClassicSearchService.findBySourceId(original.sourceId);
    expect(resolved, isNotNull);
    expect(resolved!.sourceId, original.sourceId);
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

  test('classic search sources map to one explicit reader contract', () {
    expect(
      ClassicSearchService.contextualModuleIdForSource('shanghan'),
      'shanghan',
    );
    expect(
      ClassicSearchService.contextualModuleIdForSource('jingui'),
      'jingui',
    );
    expect(
      ClassicSearchService.contextualModuleIdForSource('neijing'),
      'neijing-reading',
    );
    expect(
      ClassicSearchService.contextualModuleIdForSource('zhenjiu'),
      'zhenjiu-reading',
    );
    expect(
      ClassicSearchService.contextualModuleIdForSource('bencao'),
      'bencao-reading',
    );
    expect(
      ClassicSearchService.contextualModuleIdForSource('guji'),
      isNull,
      reason: 'Ancient-book chapters require their independent source-line map.',
    );
    expect(
      ClassicSearchService.contextualModuleIdForSource('unknown'),
      isNull,
    );

    const shanghanClause = ClassicHit(
      source: 'shanghan',
      sourceLabel: '伤寒论讲稿',
      title: '伤寒论条文2',
      asset: 'assets/shanghan/clause_001.md',
      snippet: '发热，汗出',
    );
    expect(
      ClassicSearchService.contextualAnchorIdForHit(shanghanClause),
      'shanghan:clause:002',
    );

    // Every asset-backed reader screen must use the same canonical anchor
    // builder. Only the explicit reader-module allowlist is accepted.
    const moduleAssets = <String, String>{
      'shanghan': 'assets/shanghan/clause_002.md',
      'jingui': 'assets/jingui/clause_001.md',
      'neijing-reading': 'assets/neijing/01_上古天真论.md',
      'zhenjiu-reading':
          'assets/zhenjiu_lecture/00_第一章针灸的使用时机.md',
      'bencao-reading': 'assets/bencao_lecture/sample.md',
      'yijing-reading': 'assets/yijing/1.乾为天䷀.md',
      'minggua-reading': 'assets/yijing_minggua/0.八字的排列方法.md',
    };
    for (final entry in moduleAssets.entries) {
      final moduleId = entry.key;
      final asset = entry.value;
      final expected = moduleId == 'shanghan'
          ? 'shanghan:passage:$asset'
          : '$moduleId:passage:$asset';
      expect(
        ClassicSearchService.contextualAnchorIdForReaderAsset(
          moduleId: moduleId,
          asset: asset,
        ),
        expected,
        reason: 'Reader module $moduleId must use its canonical asset prefix',
      );
    }
    expect(
      ClassicSearchService.contextualAnchorIdForReaderAsset(
        moduleId: 'unknown-reader',
        asset: 'assets/neijing/01_上古天真论.md',
      ),
      isNull,
    );
    expect(
      ClassicSearchService.contextualAnchorIdForReaderAsset(
        moduleId: 'bencao-reading',
        asset: 'assets/neijing/01_上古天真论.md',
      ),
      isNull,
      reason: 'A valid asset from another module must not be rebound.',
    );
    expect(
      ClassicSearchService.contextualAnchorIdForReaderAsset(
        moduleId: 'neijing-reading',
        asset: '   ',
      ),
      isNull,
    );
    expect(
      ClassicSearchService.contextualAnchorIdForReaderAsset(
        moduleId: 'shanghan',
        asset: 'assets/shanghan/clause_001.md',
      ),
      'shanghan:clause:002',
    );

    expect(
      ClassicSearchService.contextualAnchorIdForHit(const ClassicHit(
        source: 'guji',
        sourceLabel: '古籍原文',
        title: '古籍章节',
        bookId: 'shanghan_lun',
        chapterIndex: 1,
        snippet: '原文',
      )),
      isNull,
    );
  });

  test('reader module source IDs reverse-resolve to the exact indexed asset', () async {
    final result = await ClassicSearchService.search('丹砂');
    final original = result.hits.firstWhere(
      (hit) =>
          hit.source == 'bencao' &&
          (hit.asset ?? '').startsWith('assets/bencao_lecture/'),
    );
    final moduleId =
        ClassicSearchService.contextualModuleIdForSource(original.source);
    expect(moduleId, 'bencao-reading');
    expect(
      ClassicSearchService.contextualAnchorIdForHit(original),
      'bencao-reading:passage:${original.asset}',
      reason: 'A real indexed Bencao asset must resolve to its canonical reader anchor.',
    );

    final resolved = await ClassicSearchService.findBySourceId(
      '$moduleId:${original.asset}',
    );
    expect(resolved, isNotNull);
    expect(resolved!.source, 'bencao');
    expect(resolved.sourceId, original.sourceId);
    expect(resolved.asset, original.asset);
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
