import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/bencao_lecture_data.dart';
import 'package:nihaisha_app/data/bencao_lecture_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('本草讲稿反向索引可从药材定位到实际讲稿资产', () async {
    expect(kBenCaoLectures.length, 335);

    final index = await BenCaoLectureIndex.load();
    final hits = index.hitsFor('丹砂');
    expect(hits, isNotEmpty);
    expect(
      hits.every((hit) => hit.seq >= 0 && hit.seq < kBenCaoLectures.length),
      isTrue,
    );

    final hit = hits.first;
    expect(BenCaoLectureIndex.nameOf(hit.seq), contains('丹砂'));
    final asset = BenCaoLectureIndex.assetOf(hit.seq);
    expect(asset, startsWith('assets/bencao_lecture/'));
    expect(asset.endsWith('.md'), isTrue);
    expect((await rootBundle.loadString(asset)).trim(), isNotEmpty);
  });

  test('本草讲稿反向索引未命中时安全返回空列表', () async {
    final index = await BenCaoLectureIndex.load();
    expect(index.hitsFor('不存在的本草条目'), isEmpty);
  });
}
