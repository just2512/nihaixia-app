import '../models/ai_evidence.dart';

/// A typed candidate extracted from the existing local structured-knowledge
/// projection. Offsets point to the original, unchanged legacy text block.
class LegacyStructuredEvidenceBlock {
  const LegacyStructuredEvidenceBlock({
    required this.candidate,
    required this.startOffset,
    required this.endOffset,
  });

  final CandidateEvidence candidate;
  final int startOffset;
  final int endOffset;
}

/// Candidate adaptation plus text offsets. This adapter does not search,
/// expand queries, reorder records, change per-type selection, or rewrite text.
class LegacyStructuredEvidenceExtraction {
  LegacyStructuredEvidenceExtraction({
    required this.batch,
    required List<LegacyStructuredEvidenceBlock> blocks,
  }) : blocks = List.unmodifiable(blocks);

  final CandidateEvidenceBatch batch;
  final List<LegacyStructuredEvidenceBlock> blocks;
}

/// Turns legacy Formula/Herb/Acupuncture/Acupoint/Neijing text blocks into
/// Core-2 CandidateEvidence without changing their existing lookup semantics.
///
/// The legacy builder remains the source of truth for which records matched
/// and in what order. This class only adds stable request-scoped evidence IDs,
/// source identity, a retrieval-method label and a range into the unchanged
/// rendered context. It is an adapter, not a new retrieval implementation.
class LocalStructuredEvidencePipeline {
  static int _requestSequence = 0;

  static const _sources = <_LegacyStructuredSource>[
    _LegacyStructuredSource(
      headerPrefix: '[App方剂库 ',
      sourceIdPrefix: 'formula:',
      titlePrefix: '方名：',
      retrievalMethod: 'LOCAL_FORMULA_LEGACY_MATCH',
      matchBasis: 'LEGACY_FORMULA_NAME_ALIAS_KEYWORD_OR_COMPONENT',
      materialKind: 'formula',
      sourceKey: 'formula',
      sourceLabel: 'App 方剂库',
      assetId: 'assets/data/formulas.json',
    ),
    _LegacyStructuredSource(
      headerPrefix: '[App本草库 ',
      sourceIdPrefix: 'herb:',
      titlePrefix: '药名：',
      retrievalMethod: 'LOCAL_HERB_LEGACY_MATCH',
      matchBasis: 'LEGACY_HERB_NAME_ALIAS_OR_TERM',
      materialKind: 'herb',
      sourceKey: 'herb',
      sourceLabel: 'App 本草库',
      assetId: 'assets/data/herbs.json',
    ),
    _LegacyStructuredSource(
      headerPrefix: '[App针灸处方库 ',
      sourceIdPrefix: 'acupuncture:',
      titlePrefix: '主诉/病症：',
      retrievalMethod: 'LOCAL_ACUPUNCTURE_LEGACY_MATCH',
      matchBasis: 'LEGACY_ACUPUNCTURE_SYMPTOM_OR_ALIAS',
      materialKind: 'acupuncture_formula',
      sourceKey: 'acupuncture',
      sourceLabel: 'App 针灸处方库',
      assetId: 'assets/data/acupuncture.json',
    ),
    _LegacyStructuredSource(
      headerPrefix: '[App穴位库 ',
      sourceIdPrefix: 'acupoint:',
      titlePrefix: '穴名：',
      retrievalMethod: 'LOCAL_ACUPOINT_LEGACY_MATCH',
      matchBasis: 'LEGACY_ACUPOINT_NAME_OR_DETAIL_TERM',
      materialKind: 'acupoint',
      sourceKey: 'acupoint',
      sourceLabel: 'App 穴位库',
      assetId: 'assets/data/acupoints.json',
    ),
    _LegacyStructuredSource(
      headerPrefix: '[App内经结构化条目 ',
      sourceIdPrefix: 'neijing:',
      titlePrefix: '标题：',
      retrievalMethod: 'LOCAL_NEIJING_LEGACY_MATCH',
      matchBasis: 'LEGACY_NEIJING_TITLE_SOURCE_TEXT_OR_TAG',
      materialKind: 'classical_text',
      sourceKey: 'neijing',
      sourceLabel: 'App 内经结构化条目',
      assetId: 'lib/data/neijing_entries.dart',
    ),
  ];

  static String nextRequestId() =>
      'local-structured-request-${++_requestSequence}';

  static LegacyStructuredEvidenceExtraction extract({
    required String requestId,
    required String originalQuery,
    required String legacyContextText,
  }) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }
    if (originalQuery.trim().isEmpty) {
      throw ArgumentError.value(
        originalQuery,
        'originalQuery',
        'Must not be empty',
      );
    }

    final lines = <_LegacyLine>[];
    var offset = 0;
    for (final line in legacyContextText.split('\n')) {
      lines.add(_LegacyLine(start: offset, text: line));
      offset += line.length + 1;
    }

    final headers = <({int lineIndex, _LegacyStructuredSource source})>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].text;
      for (final source in _sources) {
        if (line.startsWith(source.headerPrefix)) {
          headers.add((lineIndex: index, source: source));
          break;
        }
      }
    }

    final candidates = <CandidateEvidence>[];
    final blocks = <LegacyStructuredEvidenceBlock>[];
    final diagnostics = <String>[];
    var skipped = 0;

    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];
      final start = lines[header.lineIndex].start;
      final nextStart = index + 1 < headers.length
          ? lines[headers[index + 1].lineIndex].start
          : legacyContextText.length;
      final fullBlock = legacyContextText.substring(start, nextStart);
      final blockText = fullBlock.trimRight();
      final end = start + blockText.length;
      final blockEndLine = index + 1 < headers.length
          ? headers[index + 1].lineIndex
          : lines.length;
      final blockLines = lines
          .skip(header.lineIndex)
          .take(blockEndLine - header.lineIndex)
          .map((line) => line.text)
          .toList(growable: false);

      String? valueAfter(String prefix) {
        for (final line in blockLines) {
          final markerIndex = line.indexOf(prefix);
          if (markerIndex >= 0) {
            final value = line.substring(markerIndex + prefix.length).trim();
            if (value.isNotEmpty && value != 'MISSING') return value;
          }
        }
        return null;
      }

      final sourceId = valueAfter('来源标识：');
      final localBacklink = valueAfter('知识库条目定位：');
      final source = header.source;
      final title = source.titlePrefix == '标题：'
          ? RegExp(r'标题：([^；\n]+)')
              .firstMatch(blockLines.join('\n'))
              ?.group(1)
              ?.trim()
          : valueAfter(source.titlePrefix);

      if (sourceId == null || !sourceId.startsWith(source.sourceIdPrefix)) {
        skipped++;
        diagnostics.add('LEGACY_STRUCTURED_SOURCE_ID_MISSING_OR_INVALID');
        continue;
      }
      if (title == null || title.isEmpty) {
        skipped++;
        diagnostics.add('LEGACY_STRUCTURED_TITLE_MISSING:${source.sourceKey}');
        continue;
      }

      final candidate = CandidateEvidence(
        evidenceId: '${requestId}:candidate-${candidates.length + 1}',
        sourceId: sourceId,
        origin: CandidateEvidenceOrigin.appData,
        materialKind: source.materialKind,
        assetId: source.assetId,
        title: title,
        excerpt: blockText,
        queryId: 'legacy-local-q1',
        retrievalMethod: source.retrievalMethod,
        matchBasis: source.matchBasis,
        // The old formatter does not expose source-record completeness.
        // Do not infer completeness from the presence of a rendered block.
        completeness: CandidateEvidenceCompleteness.unknown,
        sourceKey: source.sourceKey,
        sourceLabel: source.sourceLabel,
        localBacklink: localBacklink ?? 'MISSING',
        hasLocalBacklink: localBacklink != null,
      );
      candidates.add(candidate);
      blocks.add(
        LegacyStructuredEvidenceBlock(
          candidate: candidate,
          startOffset: start,
          endOffset: end,
        ),
      );
    }

    return LegacyStructuredEvidenceExtraction(
      batch: CandidateEvidenceBatch(
        requestId: requestId,
        originalQuery: originalQuery,
        derivedQueries: [
          DerivedEvidenceQuery(
            queryId: 'legacy-local-q1',
            query: originalQuery,
            reasons: const ['LEGACY_STRUCTURED_BUILDER_ADAPTER'],
          ),
        ],
        status: candidates.isEmpty
            ? CandidateEvidenceBatchStatus.missing
            : CandidateEvidenceBatchStatus.retrieved,
        candidates: candidates,
        diagnostics: [
          'LEGACY_STRUCTURED_BUILDER_SELECTION_PRESERVED',
          'LEGACY_STRUCTURED_TEXT_AND_ORDER_PRESERVED',
          if (skipped > 0) 'LEGACY_STRUCTURED_BLOCKS_SKIPPED:$skipped',
        ],
      ),
      blocks: blocks,
    );
  }
}

class _LegacyStructuredSource {
  const _LegacyStructuredSource({
    required this.headerPrefix,
    required this.sourceIdPrefix,
    required this.titlePrefix,
    required this.retrievalMethod,
    required this.matchBasis,
    required this.materialKind,
    required this.sourceKey,
    required this.sourceLabel,
    required this.assetId,
  });

  final String headerPrefix;
  final String sourceIdPrefix;
  final String titlePrefix;
  final String retrievalMethod;
  final String matchBasis;
  final String materialKind;
  final String sourceKey;
  final String sourceLabel;
  final String assetId;
}

class _LegacyLine {
  const _LegacyLine({required this.start, required this.text});

  final int start;
  final String text;
}
