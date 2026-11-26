import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

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

  Future<String> digestAsset(String path) async {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return sha256.convert(bytes).toString();
  }


  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupunctureRepository.load();
    await AcupointRepository.load();
    await ClassicSearchService.ensureLoaded();
  });

  Future<Map<String, Object?>> capture() async {
    final queryProvenance =
        AssistantKnowledgeContextBuilder.deriveClassicQueries(request);
    final queries = <String, Object?>{};
    for (final provenance in queryProvenance) {
      final query = provenance.query;
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
          'localBacklinkStatus':
              hit.hasLocalBacklink ? 'AVAILABLE' : 'MISSING',
        }).toList(growable: false),
      };
    }

    final formula = FormulaRepository.getByName('桂枝汤');
    final context = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      request,
      includeMedicalCases: false,
    );
    final ranking = context.rankedEvidenceSet;
    if (ranking == null) {
      throw StateError('Core-2 production retrieval did not return RankedEvidenceSet');
    }
    if (context.candidateSnapshot.length != ranking.decisions.length ||
        context.candidateSnapshot.length != context.knownEvidenceIds.length) {
      throw StateError(
        'Core-2 candidate/decision/known-evidence counts do not match',
      );
    }
    final candidateDecisionRows = <Map<String, Object?>>[];
    final candidateOrdinalByEvidenceId = <String, int>{};
    for (var index = 0; index < context.candidateSnapshot.length; index++) {
      final candidate = context.candidateSnapshot[index];
      final decision = ranking.decisions[index];
      candidateOrdinalByEvidenceId[decision.evidenceId] = index;
      candidateDecisionRows.add({
        'ordinal': index,
        'sourceId': candidate.sourceId,
        'origin': candidate.origin.name,
        'materialKind': candidate.materialKind,
        'title': candidate.title,
        'query': candidate.query,
        'queryReasons': candidate.queryReasons,
        'retrievalMethod': candidate.retrievalMethod,
        'matchBasis': candidate.matchBasis,
        'completeness': candidate.completeness.name,
        'sourceKey': candidate.sourceKey,
        'sourceLabel': candidate.sourceLabel,
        'hasLocalBacklink': candidate.hasLocalBacklink,
        'assetId': candidate.assetId,
        'bookId': candidate.bookId,
        'chapterIndex': candidate.chapterIndex,
        'chunkId': candidate.chunkId,
        'chapterPath': candidate.chapterPath,
        'disposition': decision.disposition.name,
        'reasonCode': decision.reasonCode,
        'orderIndex': decision.orderIndex,
      });
    }
    List<int> candidateOrdinalsFor(List<String> evidenceIds) {
      final ordinals = <int>[];
      for (final evidenceId in evidenceIds) {
        final ordinal = candidateOrdinalByEvidenceId[evidenceId];
        if (ordinal == null) {
          throw StateError('Core-2 audit references an unknown candidate identity');
        }
        ordinals.add(ordinal);
      }
      ordinals.sort();
      return ordinals;
    }
    final orderedDecisions = ranking.decisions.asMap().entries
        .where((entry) => entry.value.disposition.name == 'keep')
        .toList()
      ..sort((left, right) =>
          left.value.orderIndex!.compareTo(right.value.orderIndex!));
    final core2Snapshot = {
      'knownCandidateCount': context.knownEvidenceIds.length,
      'candidateDecisionRows': candidateDecisionRows,
      'strategyId': ranking.strategyId,
      'strategyVersion': ranking.strategyVersion,
      'status': ranking.status.name,
      'orderedCandidateOrdinals':
          orderedDecisions.map((entry) => entry.key).toList(growable: false),
      'presentedCandidateOrdinals': context.rankedEvidence
          .map((item) => candidateOrdinalByEvidenceId[item.evidenceId]!)
          .toList(growable: false),
      'modelVisibleSourceIds':
          context.rankedEvidence.map((item) => item.sourceId).toList(growable: false),
      'budget': {
        'unit': ranking.budget.unit.name,
        'limit': ranking.budget.limit,
        'used': ranking.budget.used,
        'applied': ranking.budget.applied,
        'omittedCandidateOrdinals':
            candidateOrdinalsFor(ranking.budget.omittedEvidenceIds),
        'truncatedCandidateOrdinals':
            candidateOrdinalsFor(ranking.budget.truncatedEvidenceIds),
      },
      'diagnostics': ranking.diagnostics,
    };

    return {
      'request': request,
      'core2': core2Snapshot,
      'formula': formula == null
          ? null
          : {
              'name': formula.name,
              'components': formula.components.map((item) => item.name).toList(),
            },
      'sourceManifest': {
        'classicIndex': {
          'asset': ClassicSearchService.assetPath,
          'sha256': await digestAsset(ClassicSearchService.assetPath),
          'entryLocator': 'App-local asset or chapter locator plus stable sourceId',
        },
        'formulaData': {
          'asset': 'assets/data/formulas.json',
          'sha256': await digestAsset('assets/data/formulas.json'),
        },
      },
      'queryProvenance':
          queryProvenance.map((item) => item.toJson()).toList(growable: false),
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
          'localBacklinkStatus':
              source.localBacklink == 'MISSING' ? 'MISSING' : 'AVAILABLE',
        }).toList(growable: false),
      },
    };
  }

  Map<String, int> countBy(List<Map> rows, String key) {
    final counts = <String, int>{};
    for (final row in rows) {
      final value = row[key]?.toString() ?? 'UNKNOWN';
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, Object?> summarize(Map<String, Object?> snapshot) {
    final rawQueries = snapshot['classicQueries']! as Map<String, Object?>;
    final queries = <String, Object?>{};
    for (final entry in rawQueries.entries) {
      final result = entry.value! as Map<String, Object?>;
      final hits = (result['hits']! as List).cast<Map>();
      queries[entry.key] = {
        'total': result['total'],
        'capturedCount': hits.length,
        'topSourceIds': hits.take(3).map((hit) => hit['sourceId']).toList(),
        'sourceCounts': countBy(hits, 'source'),
        'localBacklinkStatusCounts': countBy(hits, 'localBacklinkStatus'),
      };
    }

    final rawContext = snapshot['context']! as Map<String, Object?>;
    final sources = (rawContext['sources']! as List).cast<Map>();
    return {
      'schemaVersion': 1,
      'request': snapshot['request'],
      'formula': snapshot['formula'],
      'sourceManifest': snapshot['sourceManifest'],
      'queryProvenance': snapshot['queryProvenance'],
      'classicQueries': queries,
      'context': {
        'status': rawContext['status'],
        'sourceIds': rawContext['sourceIds'],
        'textLength': (rawContext['text']! as String).length,
        'localBacklinkStatusCounts':
            countBy(sources, 'localBacklinkStatus'),
      },
    };
  }

  test('records the origin of derived classic search queries', () {
    final provenance =
        AssistantKnowledgeContextBuilder.deriveClassicQueries('第12条 桂枝汤');
    final byQuery = {
      for (final item in provenance) item.query: item,
    };

    expect(provenance.first.query, '第12条 桂枝汤');
    expect(byQuery.containsKey('桂枝汤'), isTrue);
    expect(byQuery['第12条']!.reasons, contains('ARTICLE_NUMBER:12'));
    expect(byQuery['条文12']!.reasons, contains('ARTICLE_NUMBER:12'));
    final formula = FormulaRepository.getByName('桂枝汤');
    expect(formula, isNotNull);
    expect(
      byQuery['桂枝汤']!.reasons,
      contains('FORMULA_ID:${formula!.id}'),
    );
  });

  test('captures reproducible Guizhi Tang and Shanghan Lun retrieval baseline', () async {
    final first = await capture();
    final second = await capture();
    expect(jsonEncode(second), jsonEncode(first),
        reason: '同一 commit 的检索命中、排序、来源和上下文必须可重复');

    final core2 = first['core2']! as Map<String, Object?>;
    final candidateRows =
        (core2['candidateDecisionRows']! as List).cast<Map>();
    final orderedOrdinals =
        (core2['orderedCandidateOrdinals']! as List).cast<int>();
    final presentedOrdinals =
        (core2['presentedCandidateOrdinals']! as List).cast<int>();
    expect(candidateRows, isNotEmpty);
    expect(core2['knownCandidateCount'], candidateRows.length);
    expect(candidateRows.every((row) =>
        (row['sourceId'] as String).isNotEmpty &&
        (row['query'] as String).isNotEmpty &&
        (row['reasonCode'] as String).isNotEmpty), isTrue);
    expect(
      presentedOrdinals.every(orderedOrdinals.contains),
      isTrue,
      reason: '只有 KEEP 且完整进入本轮上下文的候选才可作为模型引用',
    );
    expect(
      candidateRows.every((row) => !row.containsKey('excerpt')),
      isTrue,
      reason: '候选审计快照不得复制知识正文或进入模型上下文',
    );
    expect(core2['strategyId'], isNotEmpty);
    expect(core2['strategyVersion'], isNotEmpty);
    expect((core2['budget']! as Map)['applied'], isTrue);

    final expectedFile = File('test/fixtures/ai_retrieval_golden_metadata.json');
    expect(expectedFile.existsSync(), isTrue,
        reason: '检索行为基线必须有可审查、可版本控制的固定夹具');
    final expected = jsonDecode(expectedFile.readAsStringSync());
    expect(
      jsonEncode(summarize(first)),
      jsonEncode(expected),
      reason: '检索数量、前序命中、资产 hash、知识库条目回链或上下文组成发生变化时必须显式审查',
    );

    expect(first['formula'], isNotNull,
        reason: '桂枝汤必须从本地方剂库解析');
    final queryResults = first['classicQueries']! as Map<String, Object?>;
    final provenance = first['queryProvenance']! as List<Object?>;
    expect(provenance, isNotEmpty);
    expect((provenance.first as Map)['query'], request);
    expect(queryResults.keys.toSet(), provenance
        .map((item) => (item as Map)['query'] as String)
        .toSet());
    expect(queryResults.containsKey('桂枝汤'), isTrue);
    expect(queryResults.containsKey('伤寒论'), isTrue);
    for (final query in queryResults.keys) {
      final result = queryResults[query]! as Map<String, Object?>;
      expect(result['total'], isA<int>());
      expect(result['hits'], isA<List<Object?>>());
      final hits = (result['hits']! as List).cast<Map>();
      expect(
        hits.every((hit) =>
            hit['localBacklink'] is String &&
            (hit['localBacklink'] as String).isNotEmpty &&
            hit['localBacklink'] != 'MISSING'),
        isTrue,
        reason: '$query 的命中必须能回链到 App 本地知识条目',
      );
    }
    final manifest = first['sourceManifest']! as Map<String, Object?>;
    expect((manifest['classicIndex']! as Map)['sha256'], isA<String>());
    expect((manifest['formulaData']! as Map)['sha256'], isA<String>());
    final context = first['context']! as Map<String, Object?>;
    expect(context['text'], isA<String>());
    expect((context['text'] as String), isNotEmpty);

    final output = File('build/ai-retrieval-golden/current.json');
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(first),
    );
    // The full text snapshot remains a CI artifact to avoid checking in
    // copyrighted excerpts. Metadata-only expectations live in the fixture.
    // ignore: avoid_print
    print('AI_RETRIEVAL_GOLDEN_SNAPSHOT=${output.path}');
  });
}
