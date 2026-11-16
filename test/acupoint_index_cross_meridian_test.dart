import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/zhenjiu_lecture_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('跨经同名穴位的讲稿命中必须归属到正确经络章节', () async {
    final index = await ZhenJiuLectureIndex.load();
    const expectedChapterByPoint = <String, String>{
      '足五里': '足厥阴肝经',
      '手五里': '手阳明大肠经',
      '膝阳关': '足少阳胆经',
      '腰阳关': '督脉',
      '足通谷': '足太阳膀胱经',
      '腹通谷': '足少阴肾经',
      '头窍阴': '足少阳胆经',
      '足窍阴': '足少阳胆经',
      '譩譆': '足太阳膀胱经',
    };

    for (final entry in expectedChapterByPoint.entries) {
      final hits = index.hitsFor(entry.key);
      expect(hits, isNotEmpty, reason: '${entry.key} 应有讲稿命中');
      for (final hit in hits) {
        final chapter = ZhenJiuLectureIndex.nameOf(hit.seq);
        expect(
          chapter,
          contains(entry.value),
          reason: '${entry.key} 不应归入错误章节：$chapter',
        );
      }
    }
  });
}
