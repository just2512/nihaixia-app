import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/classic_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const request = '查桂枝汤组成，并找《伤寒论》对应条文';

  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupunctureRepository.load();
    await AcupointRepository.load();
    await ClassicSearchService.ensureLoaded();
  });

  Future<Map<String, Object?>> capture() async {
    final queries = <String, Object?>{};
    for (final query in [
      request,
      '桂枝汤',
      '伤寒论',
    ]) {
      final result = await ClassicSearchService.search(query);
      queries[query] = {
        'total': result.total,
        'hits': result.hits.map((hit) => {
          'sourceId': hit.sourceId,
          'source': hit.source,
          'sourceLabel': hit.sourceLabel,
          'title': hit.title,
          'asset': hit.asset,
          'bookId': hit.bookId,
          'chapterIndex': hit.chapterIndex,
          'snippet': hit.snippet,
          'localBacklink': hit.localBacklink,
          'locatorStatus': hit.locatorStatus,
        }).toList(growable: false),
      };
    }

    final formula = FormulaRepository.getByName('桂枝汤');
    final context = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      request,
      includeMedicalCases: false,
    );

    return {
      'request': request,
      'formula': formula == null
          ? null
          : {
              'name': formula.name,
              'components': formula.components.map((item) => item.name).toList(),
            },
      'classicQueries': queries,
      'context': {
        'status': context.statusLabel,
        'text': context.text,
        'sourceIds': context.sourceIds,
        'sources': context.sources.map((source) => {
          'sourceId': source.sourceId,
          'sourceKind': source.sourceKind,
          'sourceLabel': source.sourceLabel,
          'title': source.title,
          'localBacklink': source.localBacklink,
          'locatorStatus': source.locatorStatus,
          'sourceVerificationStatus': source.sourceVerificationStatus,
          'bibliographicLocatorVerified': source.bibliographicLocatorVerified,
        }).toList(growable: false),
      },
    };
  }

  test('captures reproducible Guizhi Tang and Shanghan Lun retrieval baseline', () async {
    final first = await capture();
    final second = await capture();
    expect(jsonEncode(second), jsonEncode(first),
        reason: '同一 commit 的检索命中、排序、来源和上下文必须可重复');

    expect(first['formula'], isNotNull,
        reason: '桂枝汤必须从本地方剂库解析');
    final queryResults = first['classicQueries']! as Map<String, Object?>;
    for (final query in [request, '桂枝汤', '伤寒论']) {
      final result = queryResults[query]! as Map<String, Object?>;
      expect(result['total'], isA<int>());
      expect(result['hits'], isA<List<Object?>>());
    }
    final context = first['context']! as Map<String, Object?>;
    expect(context['text'], isA<String>());
    expect((context['text'] as String), isNotEmpty);

    final output = File('build/ai-retrieval-golden/current.json');
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(first),
    );
    // The snapshot is a CI artifact, not a checked-in fixture. It must be
    // reviewed before being promoted to a permanent golden expectation.
    // ignore: avoid_print
    print('AI_RETRIEVAL_GOLDEN_SNAPSHOT=${output.path}');
  });
}
