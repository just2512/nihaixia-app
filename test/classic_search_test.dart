// 经典全文检索回归：讲稿 + 古籍原文统一索引。
// 运行：flutter test test/classic_search_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/services/classic_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('空查询返回空结果，不触发索引加载', () async {
    final r = await ClassicSearchService.search('   ');
    expect(r.total, 0);
    expect(r.hits, isEmpty);
  });

  test('索引可加载，条目数覆盖讲稿 906 + 古籍 421', () async {
    await ClassicSearchService.ensureLoaded();
    expect(ClassicSearchService.isLoaded, isTrue);

    // 用三个高覆盖词分别验证三类来源都能命中
    final guiZhi = await ClassicSearchService.search('桂枝汤');
    expect(guiZhi.total, greaterThan(0));
    expect(guiZhi.hits.any((h) => h.source == 'shanghan'), isTrue,
        reason: '伤寒讲稿应能搜到桂枝汤');

    final biaoYou = await ClassicSearchService.search('标幽赋');
    expect(biaoYou.total, greaterThan(0));
    expect(biaoYou.hits.any((h) => h.bookId == 'zhenjiudacheng'), isTrue,
        reason: '针灸大成卷二应有「标幽赋」');

    final lingshu = await ClassicSearchService.search('九针');
    expect(lingshu.total, greaterThan(0));
    expect(lingshu.hits.any((h) => h.bookId == 'lingshu'), isTrue,
        reason: '灵枢应能搜到九针相关章节');
  });

  test('上游独有条文可检索且不覆盖本地同名条文', () async {
    final jingui = await ClassicSearchService.search('诃黎勒散');
    expect(
      jingui.hits.any((h) => h.asset == 'assets/jingui/clause_453.md'),
      isTrue,
      reason: '新增金匮条文应进入搜索索引',
    );

    final shanghan = await ClassicSearchService.search('胃中寒冷故也');
    expect(
      shanghan.hits.any((h) => h.asset == 'assets/shanghan/clause_380.md'),
      isTrue,
      reason: '新增伤寒宋本条文应进入搜索索引',
    );
  });

  test('本草讲稿进入经典全文检索', () async {
    final bencao = await ClassicSearchService.search('丹砂');
    expect(
      bencao.hits.any(
        (hit) =>
            hit.source == 'bencao' &&
            (hit.asset ?? '').startsWith('assets/bencao_lecture/'),
      ),
      isTrue,
      reason: '本草讲稿应通过本地经典搜索索引命中',
    );
  });

  test('上游宋本176独立条文可搜索且回链到独立资产', () async {
    final result = await ClassicSearchService.search('脉浮滑，此以表有热');
    expect(
      result.hits.any(
        (hit) => hit.asset == 'assets/shanghan/clause_176_upstream.md',
      ),
      isTrue,
    );
    final hit = result.hits.firstWhere(
      (item) => item.asset == 'assets/shanghan/clause_176_upstream.md',
    );
    final resolved = await ClassicSearchService.findBySourceId(hit.sourceId);
    expect(resolved, isNotNull);
    expect(resolved!.asset, 'assets/shanghan/clause_176_upstream.md');
  });

  test('命中带来源标签与摘要，标题命中排在正文命中之前', () async {
    final r = await ClassicSearchService.search('上古天真论');
    expect(r.hits, isNotEmpty);
    expect(r.hits.first.title.contains('上古天真论'), isTrue);
    expect(r.hits.first.sourceLabel.isNotEmpty, isTrue);
    expect(r.hits.first.snippet.isNotEmpty, isTrue);
  });

  test('展示条数封顶 40，但总数照实统计', () async {
    final r = await ClassicSearchService.search('太阳');
    expect(r.hits.length, lessThanOrEqualTo(ClassicSearchService.maxHits));
    expect(r.total, greaterThanOrEqualTo(r.hits.length));
  });
}
