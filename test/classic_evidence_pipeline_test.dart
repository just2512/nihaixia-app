import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/classic_evidence_pipeline.dart';
import 'package:nihaisha_app/services/classic_search_service.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const request = '查桂枝汤组成，并找《伤寒论》对应条文';

  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupointRepository.load();
    await ClassicSearchService.ensureLoaded();
  });

  test('classic candidate batch preserves legacy first-four evidence order', () async {
    final provenance =
        AssistantKnowledgeContextBuilder.deriveClassicQueries(request);
    final derivedQueries = [
      for (var index = 0; index < provenance.length; index++)
        DerivedEvidenceQuery(
          queryId: 'q${index + 1}',
          query: provenance[index].query,
          reasons: provenance[index].reasons,
        ),
    ];

    final batch = await ClassicEvidencePipeline.retrieveClassicIndexCandidates(
      requestId: 'test-request',
      originalQuery: request,
      derivedQueries: derivedQueries,
    );

    // Reproduce only the legacy ordering contract: derived query order,
    // result.hits order, existing identity-based deduplication, first four.
    final expectedSourceIds = <String>[];
    final seen = <String>{};
    for (final query in derivedQueries) {
      if (query.query.trim().length < 2) continue;
      final result = await ClassicSearchService.search(query.query);
      for (final hit in result.hits) {
        final identity =
            '${hit.source}|${hit.asset ?? hit.bookId}|'
            '${hit.chapterIndex}|${hit.title}';
        if (!seen.add(identity)) continue;
        expectedSourceIds.add(hit.sourceId);
        if (expectedSourceIds.length >=
            ClassicEvidencePipeline.legacyContextHitLimit) {
          break;
        }
      }
      if (expectedSourceIds.length >=
          ClassicEvidencePipeline.legacyContextHitLimit) {
        break;
      }
    }

    expect(batch.originalQuery, request);
    expect(batch.derivedQueries.map((item) => item.query).toList(),
        provenance.map((item) => item.query).toList());
    expect(batch.candidates.length, 40);
    expect(batch.status, CandidateEvidenceBatchStatus.partial);
    expect(
      batch.diagnostics,
      contains(startsWith('CLASSIC_INDEX_HIT_CAP:')),
    );
    expect(
      batch.diagnostics,
      contains(startsWith('LEGACY_QUERY_EARLY_STOP_AFTER_FOUR:')),
    );
    expect(
      batch.candidates
          .take(ClassicEvidencePipeline.legacyContextHitLimit)
          .map((item) => item.sourceId)
          .toList(),
      expectedSourceIds,
    );
    expect(
      batch.candidates.map((item) => item.evidenceId).toSet().length,
      batch.candidates.length,
    );
    expect(
      batch.candidates.every(
        (item) =>
            item.origin == CandidateEvidenceOrigin.appData &&
            item.matchBasis == 'UNKNOWN' &&
            item.completeness == CandidateEvidenceCompleteness.unknown,
      ),
      isTrue,
    );
  });
}
