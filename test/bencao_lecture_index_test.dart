import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/bencao_lecture_data.dart';
import 'package:nihaisha_app/data/bencao_lecture_index.dart';
import 'package:nihaisha_app/data/herb_repository.dart';

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

  test('本草反向索引所有序号有效且仅保留一个本地药库未匹配项', () async {
    await HerbRepository.load();
    final raw = jsonDecode(
      await rootBundle.loadString('assets/bencao_lecture/herb_index.json'),
    ) as Map<String, dynamic>;
    final entries = raw.entries.where((entry) => !entry.key.startsWith('_'));
    final indexedNames = entries.map((entry) => entry.key).toSet();
    final localHerbs =
        HerbRepository.getAll().map((herb) => herb.name).toSet();

    expect(indexedNames.length, 440);
    expect(localHerbs.length, 465);
    expect(
      indexedNames.difference(localHerbs),
      {'石菖蒲（九节菖蒲）'},
      reason: '无本地药材条目时不伪造或错误建立关联',
    );

    var referenceCount = 0;
    for (final entry in entries) {
      final rows = (entry.value as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final seqs = rows.map((row) => row['s'] as int).toList();
      expect(seqs, isNotEmpty, reason: entry.key);
      expect(seqs.toSet().length, seqs.length,
          reason: '同一药材不得重复指向同一篇：${entry.key}');
      for (final row in rows) {
        final seq = row['s'] as int;
        final count = row['n'] as int;
        expect(seq >= 0 && seq < kBenCaoLectures.length, isTrue,
            reason: '越界讲稿序号：${entry.key} -> $seq');
        expect(count > 0, isTrue, reason: '非法提及次数：${entry.key}');
        referenceCount++;
      }
    }
    expect(referenceCount, 2301);
  });

  test('本草讲稿反向索引未命中时安全返回空列表', () async {
    final index = await BenCaoLectureIndex.load();
    expect(index.hitsFor('不存在的本草条目'), isEmpty);
  });
}
