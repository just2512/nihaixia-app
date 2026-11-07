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
}
