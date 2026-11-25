import '../data/acupuncture_repository.dart';
import '../data/acupoint_repository.dart';
import '../data/formula_repository.dart';
import '../data/guji_data.dart';
import '../data/medical_case_data.dart';
import '../models/ai_evidence.dart';
import '../models/evidence_ranking_decision.dart';
import 'classic_evidence_pipeline.dart';
import 'multi_source_evidence_pipeline.dart';
import 'source_aware_legacy_evidence_ranker.dart';
import 'guji_evidence_pipeline.dart';
import 'medical_case_evidence_pipeline.dart';
import 'classic_search_service.dart';
import '../data/herb_repository.dart';
import '../data/neijing_entries.dart';
import '../models/formula.dart';
import '../models/acupuncture.dart';
import '../models/acupoint_detail.dart';


/// A source resolved to a concrete entry in the App's local knowledge base.
/// The source ID and backlink identify the exact entry used for this answer.
class AssistantKnowledgeSourceReference {
  const AssistantKnowledgeSourceReference({
    required this.sourceId,
    required this.sourceLabel,
    required this.title,
    required this.localBacklink,
    this.sourceKind = 'classic_text',
  });

  final String sourceId;
  final String sourceLabel;
  final String title;
  final String localBacklink;
  final String sourceKind;

  String toCitationText() {
    final locatorLabel =
        localBacklink == 'MISSING' ? '当前条目不可定位' : '可定位';
    final sourceType = switch (sourceKind) {
      'lecture' => '课程讲稿/整理讲义（学习资料）',
      'classic_text' => 'App 古籍文本知识条目',
      'medical_case' => 'App 医案库整理条目',
      _ => 'App 本地知识库数据（$sourceKind）',
    };
    return '- $sourceLabel｜$title\n'
        '  资料类型：$sourceType\n'
        '  知识库条目定位：$localBacklink（$locatorLabel）\n'
        '  来源标识：$sourceId';
  }
}

enum AssistantKnowledgeRetrievalStatus { noResults, retrieved, partial, failed }

/// The exact candidate identity and local source identity handed from
/// Core-2 to a request-local reasoning adapter.
class AssistantKnowledgeEvidenceReference {
  const AssistantKnowledgeEvidenceReference({
    required this.evidenceId,
    required this.sourceId,
  });

  final String evidenceId;
  final String sourceId;
}

/// Retrieval materialization plus the evidence IDs that were fully included
/// in the bounded model context. Candidate IDs include KEEP and DROP decisions.
class AssistantKnowledgeContextBuildResult {
  AssistantKnowledgeContextBuildResult({
    required this.text,
    required List<String> knownEvidenceIds,
    required List<AssistantKnowledgeEvidenceReference> rankedEvidence,
    this.rankedEvidenceSet,
  })  : knownEvidenceIds = List.unmodifiable(knownEvidenceIds),
        rankedEvidence = List.unmodifiable(rankedEvidence);

  final String text;
  final List<String> knownEvidenceIds;
  final List<AssistantKnowledgeEvidenceReference> rankedEvidence;

  /// Full source-ranking decisions, strategy and final context-budget accounting.
  /// This is App audit data; model-visible references remain [rankedEvidence].
  final RankedEvidenceSet? rankedEvidenceSet;

  String get evidenceIndexContext => rankedEvidence.isEmpty
      ? ''
      : '【本轮已完整提供、允许引用的证据 ID】\n' +
          rankedEvidence
              .map((item) => '- evidenceId=${item.evidenceId}; sourceId=${item.sourceId}')
              .join('\n');
}


class AssistantKnowledgeQueryProvenance {
  const AssistantKnowledgeQueryProvenance({
    required this.query,
    required this.reasons,
  });

  final String query;
  final List<String> reasons;

  Map<String, Object?> toJson() => {
        'query': query,
        'reasons': reasons,
      };
}


/// Retrieval text plus status and the exact, resolvable source IDs used for this turn.
class AssistantKnowledgeContextResult {
  const AssistantKnowledgeContextResult({
    required this.text,
    this.sources = const [],
    this.status = AssistantKnowledgeRetrievalStatus.noResults,
    this.failureMessage,
    this.knownEvidenceIds = const [],
    this.rankedEvidence = const [],
    this.rankedEvidenceSet,
  });

  final String text;
  final List<AssistantKnowledgeSourceReference> sources;
  final AssistantKnowledgeRetrievalStatus status;
  final String? failureMessage;
  final List<String> knownEvidenceIds;
  final List<AssistantKnowledgeEvidenceReference> rankedEvidence;

  /// Original KEEP/DROP decisions plus the final character-bound presentation
  /// outcome. It never changes source identity or verification state.
  final RankedEvidenceSet? rankedEvidenceSet;

  List<String> get rankedEvidenceIds =>
      List.unmodifiable(rankedEvidence.map((item) => item.evidenceId));

  Map<String, String> get sourceIdByEvidenceId => Map.unmodifiable({
        for (final item in rankedEvidence) item.evidenceId: item.sourceId,
      });

  String get evidenceIndexContext => rankedEvidence.isEmpty
      ? ''
      : '【本轮已完整提供、允许引用的证据 ID】\n' +
          rankedEvidence
              .map((item) => '- evidenceId=${item.evidenceId}; sourceId=${item.sourceId}')
              .join('\n');

  /// Stable wire/UI value shared with tool execution status metadata.
  String get statusLabel => switch (status) {
        AssistantKnowledgeRetrievalStatus.noResults => 'NO_RESULTS',
        AssistantKnowledgeRetrievalStatus.retrieved => 'RETRIEVED',
        AssistantKnowledgeRetrievalStatus.partial => 'PARTIAL',
        AssistantKnowledgeRetrievalStatus.failed => 'FAILED',
      };

  List<String> get sourceIds =>
      List.unmodifiable(sources.map((source) => source.sourceId));

  String get citationFooter => sources.isEmpty
      ? ''
      : '\n\n本轮引用的知识库条目（可按条目定位和来源标识回查）：\n' +
          sources.map((source) => source.toCitationText()).join('\n');
}

/// Bounded keyword retrieval from the app's bundled TCM knowledge data.
/// Returns source-labelled excerpts, never a diagnosis or prescription.
class AssistantKnowledgeContextBuilder {
  static const int maxContextCharacters = 6500;
  static const int maxFormulaEntries = 4;
  static const int maxHerbEntries = 5;
  static const int maxAcupunctureEntries = 3;
  static const int maxAcupointEntries = 3;
  static const int maxNeijingEntries = 3;

  // Do not scan the full classic/case corpus for generic chat turns. The
  // conversation model already has prior-turn context; retrieval is only
  // needed when the current turn contains a TCM domain cue.
  static const Set<String> _knowledgeQueryCues = {
    '中医', '伤寒', '金匮', '黄帝内经', '素问', '灵枢', '脏腑', '经络',
    '穴位', '方剂', '经方', '中药', '药材', '医案', '古籍', '经典', '条文',
    '子午流注', '纳子法', '纳甲法',
    '五运六气', '脉象', '舌象', '太阳', '阳明', '少阳', '太阴', '少阴',
    '厥阴', '咳嗽', '头痛', '头晕', '腹痛', '腹胀', '失眠', '发热',
    '恶寒', '口苦', '胸闷', '尿频', '便秘', '腹泻', '心悸', '呕吐',
  };

  /// Cheap deterministic gate for deciding whether a user turn needs the
  /// bundled TCM retrieval path. Ordinary chat and non-TCM metaphysics queries
  /// do not load/search the classic corpus.
  static bool shouldRetrieveForQuery(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return false;
    return _knowledgeQueryCues.any(normalized.contains) ||
        FormulaRepository.getAll().any((item) => normalized.contains(item.name)) ||
        HerbRepository.getAll().any((item) => normalized.contains(item.name)) ||
        AcupointRepository.getAll().any((item) => normalized.contains(item.name));
  }

  /// Builds bounded retrieval context and resolves every emitted classic
  /// source ID back to the bundled index before exposing it as a citation.
  /// Unknown IDs are omitted rather than presented as valid references.
  static Future<AssistantKnowledgeContextResult> buildWithSourcesAsync(
    String query, {
    bool includeMedicalCases = true,
  }) async {
    late final AssistantKnowledgeContextBuildResult built;
    try {
      built = await buildWithEvidenceAsync(
        query,
        includeMedicalCases: includeMedicalCases,
      );
    } catch (error) {
      return AssistantKnowledgeContextResult(
        text: '',
        status: AssistantKnowledgeRetrievalStatus.failed,
        failureMessage: error.toString(),
      );
    }
    final text = built.text;
    if (text.isEmpty) {
      return AssistantKnowledgeContextResult(
        text: '',
        status: AssistantKnowledgeRetrievalStatus.noResults,
        knownEvidenceIds: built.knownEvidenceIds,
        rankedEvidence: built.rankedEvidence,
        rankedEvidenceSet: built.rankedEvidenceSet,
      );
    }
    final sourceIds = <String>{};
    for (final line in text.split('\n')) {
      const marker = '来源标识：';
      final markerIndex = line.indexOf(marker);
      if (markerIndex < 0) continue;
      final sourceId = line.substring(markerIndex + marker.length).trim();
      if (sourceId.isNotEmpty && sourceId != 'MISSING') {
        sourceIds.add(sourceId);
      }
    }
    final sources = <AssistantKnowledgeSourceReference>[];
    for (final sourceId in sourceIds) {
      try {
        if (sourceId.startsWith('formula:')) {
          final id = sourceId.substring('formula:'.length);
          final matches = FormulaRepository.getAll().where((item) => item.id == id);
          if (matches.isNotEmpty) {
            final formula = matches.first;
            sources.add(AssistantKnowledgeSourceReference(
              sourceId: sourceId,
              sourceLabel: 'App 方剂库',
              title: formula.name,
              localBacklink: 'assets/data/formulas.json#id=$id',
              sourceKind: 'formula',
            ));
          }
          continue;
        }
        if (sourceId.startsWith('herb:')) {
          final name = sourceId.substring('herb:'.length);
          final matches = HerbRepository.getAll().where((item) => item.name == name);
          if (matches.isNotEmpty) {
            sources.add(AssistantKnowledgeSourceReference(
              sourceId: sourceId,
              sourceLabel: 'App 本草库',
              title: matches.first.name,
              localBacklink: 'assets/data/herbs.json#name=$name',
              sourceKind: 'herb',
            ));
          }
          continue;
        }
        if (sourceId.startsWith('acupuncture:')) {
          final parts = sourceId.split(':');
          if (parts.length != 3) continue;
          final categoryId = parts[1];
          final id = int.tryParse(parts[2]);
          if (id == null) continue;
          final categories = AcupunctureRepository.getAll()
              .where((category) => category.id == categoryId);
          if (categories.isNotEmpty) {
            final entries = categories.first.entries.where((item) => item.id == id);
            if (entries.isNotEmpty) {
              final entry = entries.first;
              sources.add(AssistantKnowledgeSourceReference(
                sourceId: sourceId,
                sourceLabel: 'App 针灸处方库 · ${entry.sourceLabel}',
                title: entry.symptom,
                localBacklink:
                    'assets/data/acupuncture.json#category=$categoryId&id=$id',
                sourceKind: 'acupuncture',
              ));
            }
          }
          continue;
        }
        if (sourceId.startsWith('acupoint:')) {
          final name = sourceId.substring('acupoint:'.length);
          final matches = AcupointRepository.getAll().where((item) => item.name == name);
          if (matches.isNotEmpty) {
            sources.add(AssistantKnowledgeSourceReference(
              sourceId: sourceId,
              sourceLabel: 'App 穴位库',
              title: matches.first.name,
              localBacklink: 'assets/data/acupoints.json#name=$name',
              sourceKind: 'acupoint',
            ));
          }
          continue;
        }
        if (sourceId.startsWith('neijing:')) {
          final id = sourceId.substring('neijing:'.length);
          final matches = kNeijingEntries.where((item) => item.id == id);
          if (matches.isNotEmpty) {
            final entry = matches.first;
            sources.add(AssistantKnowledgeSourceReference(
              sourceId: sourceId,
              sourceLabel: 'App 内经结构化条目',
              title: entry.title,
              localBacklink: 'lib/data/neijing_entries.dart#id=$id',
              sourceKind: 'neijing',
            ));
          }
          continue;
        }
        if (sourceId.startsWith('guji:')) {
          final parts = sourceId.split(':');
          if (parts.length != 3) continue;
          final bookId = parts[1];
          final chapterIndex = int.tryParse(parts[2]);
          if (chapterIndex == null || chapterIndex < 0) continue;
          GujiBook? matchedBook;
          for (final book in kGujiBooks) {
            if (book.id == bookId) {
              matchedBook = book;
              break;
            }
          }
          if (matchedBook == null) continue;
          final chapter = await GujiRepository.chapterAtIndex(
            matchedBook,
            chapterIndex,
          );
          if (chapter == null) continue;
          sources.add(AssistantKnowledgeSourceReference(
            sourceId: sourceId,
            sourceLabel: matchedBook.title,
            title: chapter.title,
            localBacklink: 'guji:$bookId#chapter:$chapterIndex',
            sourceKind: 'classic_text',
          ));
          continue;
        }
        if (sourceId.startsWith('medical_case:')) {
          final sequence = int.tryParse(
            sourceId.substring('medical_case:'.length),
          );
          if (sequence == null) continue;
          final cases = await getAllMedicalCases();
          MedicalCase? matchedCase;
          for (final medicalCase in cases) {
            if (medicalCase.seq == sequence) {
              matchedCase = medicalCase;
              break;
            }
          }
          if (matchedCase == null) continue;
          sources.add(AssistantKnowledgeSourceReference(
            sourceId: sourceId,
            sourceLabel: 'App 医案库',
            title: matchedCase.displayName,
            localBacklink: 'medical_case:$sequence',
            sourceKind: 'medical_case',
          ));
          continue;
        }
        final hit = await ClassicSearchService.findBySourceId(sourceId);
        if (hit == null) continue;
        sources.add(AssistantKnowledgeSourceReference(
          sourceId: hit.sourceId,
          sourceLabel: hit.sourceLabel,
          title: hit.title,
          localBacklink: hit.localBacklink,
          sourceKind: hit.asset != null ? 'lecture' : 'classic_text',
        ));
      } catch (_) {
        // A failed reverse lookup is not a citation. Keep the retrieval text,
        // but do not persist an unresolvable source identifier.
      }
    }
    final status = sources.isEmpty || sources.length < sourceIds.length
        ? AssistantKnowledgeRetrievalStatus.partial
        : AssistantKnowledgeRetrievalStatus.retrieved;
    final resolvedSourceIds = sources.map((source) => source.sourceId).toSet();
    final resolvedRankedEvidence = built.rankedEvidence
        .where((item) => resolvedSourceIds.contains(item.sourceId))
        .toList(growable: false);
    return AssistantKnowledgeContextResult(
      text: text,
      sources: List.unmodifiable(sources),
      status: status,
      knownEvidenceIds: built.knownEvidenceIds,
      rankedEvidence: List.unmodifiable(resolvedRankedEvidence),
      rankedEvidenceSet: built.rankedEvidenceSet,
    );
  }


  /// Returns the exact classic-index query sequence used by [buildAsync],
  /// including why each derived query was added. This is observability only:
  /// it must not change matching, ranking, truncation, or source resolution.
  static List<AssistantKnowledgeQueryProvenance> deriveClassicQueries(
    String query,
  ) {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final reasons = <String, List<String>>{};
    void add(String value, String reason) {
      final entries = reasons.putIfAbsent(value, () => <String>[]);
      if (!entries.contains(reason)) entries.add(reason);
    }

    add(normalized, 'ORIGINAL_QUERY');
    for (final formula in FormulaRepository.getAll()) {
      if (normalized.contains(formula.name)) {
        add(formula.name, 'FORMULA_ID:${formula.id}');
      }
    }
    for (final herb in HerbRepository.getAll()) {
      if (normalized.contains(herb.name)) {
        add(herb.name, 'HERB_NAME:${herb.name}');
      }
    }
    for (final point in AcupointRepository.getAll()) {
      if (normalized.contains(point.name)) {
        add(point.name, 'ACUPOINT_NAME:${point.name}');
      }
    }
    for (final phrase in const [
      '太阳与阳明合病',
      '太阳与少阳合病',
      '阳明与少阳合病',
      '三阳合病',
      '二阳并病',
      '少阴病',
      '灵枢',
      '针灸大成',
      '伤寒论',
      '金匮要略',
    ]) {
      if (normalized.contains(phrase)) {
        add(phrase, 'DOMAIN_PHRASE:$phrase');
      }
    }
    for (final match in RegExp(r'(?:第|条文)\s*(\d+)\s*条?').allMatches(normalized)) {
      final number = match.group(1);
      if (number == null) continue;
      add('第${number}条', 'ARTICLE_NUMBER:$number');
      add('条文$number', 'ARTICLE_NUMBER:$number');
    }

    return List.unmodifiable([
      for (final entry in reasons.entries)
        AssistantKnowledgeQueryProvenance(
          query: entry.key,
          reasons: List.unmodifiable(entry.value),
        ),
    ]);
  }

  /// Extends fast in-memory retrieval with bundled classical-text and
  /// medical-case learning records.
  static Future<String> buildAsync(
    String query, {
    bool includeMedicalCases = true,
  }) async =>
      (await buildWithEvidenceAsync(
        query,
        includeMedicalCases: includeMedicalCases,
      )).text;

  /// Returns the legacy text projection plus request-local evidence identity.
  /// [rankedEvidence] contains only complete evidence blocks that survived the
  /// existing 6,500-character context bound; known IDs also include dropped
  /// candidates so the reasoning layer can validate omittedEvidenceIds.
  static Future<AssistantKnowledgeContextBuildResult> buildWithEvidenceAsync(
    String query, {
    bool includeMedicalCases = true,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return AssistantKnowledgeContextBuildResult(
        text: '',
        knownEvidenceIds: const [],
        rankedEvidence: const [],
      );
    }
    final base = build(normalized);
    if (!shouldRetrieveForQuery(normalized)) {
      return AssistantKnowledgeContextBuildResult(
        text: base,
        knownEvidenceIds: const [],
        rankedEvidence: const [],
      );
    }
    final buffer = StringBuffer();
    if (base.isNotEmpty) {
      buffer.writeln(base.length > 3500 ? base.substring(0, 3500) : base);
    }

    final terms = <String>{normalized};
    for (final term in normalized
        .split(RegExp(r'[，。！？、；：,.!?;\s]+'))
        .map((value) => value.trim())
        .where((value) => value.length >= 2)) {
      terms.add(term);
    }
    for (final formula in FormulaRepository.getAll()) {
      if (normalized.contains(formula.name)) terms.add(formula.name);
      for (final alias in formula.alias.split(',')) {
        final value = alias.trim();
        if (value.length >= 2 && normalized.contains(value)) terms.add(value);
      }
    }
    for (final herb in HerbRepository.getAll()) {
      if (normalized.contains(herb.name)) terms.add(herb.name);
    }
    for (final point in AcupointRepository.getAll()) {
      if (normalized.contains(point.name)) terms.add(point.name);
    }

    final queryProvenance = deriveClassicQueries(normalized);
    final evidenceBatch = await ClassicEvidencePipeline.retrieveClassicIndexCandidates(
      requestId: ClassicEvidencePipeline.nextRequestId(),
      originalQuery: normalized,
      derivedQueries: [
        for (var index = 0; index < queryProvenance.length; index++)
          DerivedEvidenceQuery(
            queryId: 'q${index + 1}',
            query: queryProvenance[index].query,
            reasons: queryProvenance[index].reasons,
          ),
      ],
    );
    if (evidenceBatch.diagnostics.any(
      (diagnostic) => diagnostic.startsWith('CLASSIC_SEARCH_FAILED:'),
    )) {
      buffer.writeln('[App经典全文索引] 索引读取失败，状态 MISSING。');
    }

    final requestedGujiBooks = kGujiBooks.where((book) {
      if (normalized.contains(book.title)) return true;
      if (book.id == 'lingshu' && normalized.contains('灵枢')) return true;
      if (book.id == 'zhenjiudacheng' &&
          (normalized.contains('针灸大成') || normalized.contains('针灸古籍'))) {
        return true;
      }
      return false;
    }).toList(growable: false);

    // Build source batches in the established user-visible legacy order:
    // classic index, each explicitly requested Guji book, then medical cases.
    // Aggregation only namespaces IDs and preserves this caller-supplied order.
    final sourceBatches = <CandidateEvidenceBatch>[evidenceBatch];
    final failedGujiBookIds = <String>{};
    for (final book in requestedGujiBooks) {
      final batchRequestId = '${evidenceBatch.requestId}:${book.id}';
      try {
        final chapters = await GujiRepository.chaptersOf(book);
        sourceBatches.add(
          GujiEvidencePipeline.retrieveCandidates(
            requestId: batchRequestId,
            originalQuery: normalized,
            book: book,
            terms: terms.toList(growable: false),
            chapters: chapters,
          ),
        );
      } catch (_) {
        failedGujiBookIds.add(book.id);
        sourceBatches.add(
          CandidateEvidenceBatch(
            requestId: batchRequestId,
            originalQuery: normalized,
            derivedQueries: const [],
            status: CandidateEvidenceBatchStatus.failed,
            candidates: const [],
            diagnostics: const ['GUIJI_CHAPTER_READ_FAILED'],
          ),
        );
      }
    }

    List<MedicalCase>? medicalCases;
    var medicalCaseReadFailed = false;
    if (includeMedicalCases) {
      try {
        medicalCases = await getAllMedicalCases();
        sourceBatches.add(
          MedicalCaseEvidencePipeline.retrieveCandidates(
            requestId: '${evidenceBatch.requestId}:medical-cases',
            originalQuery: normalized,
            terms: terms.toList(growable: false),
            cases: medicalCases,
          ),
        );
      } catch (_) {
        medicalCaseReadFailed = true;
        sourceBatches.add(
          CandidateEvidenceBatch(
            requestId: '${evidenceBatch.requestId}:medical-cases',
            originalQuery: normalized,
            derivedQueries: const [],
            status: CandidateEvidenceBatchStatus.failed,
            candidates: const [],
            diagnostics: const ['MEDICAL_CASE_READ_FAILED'],
          ),
        );
      }
    }

    final combinedBatch = MultiSourceEvidencePipeline.combine(
      requestId: '${evidenceBatch.requestId}:all-sources',
      originalQuery: normalized,
      sourceBatches: sourceBatches,
    );
    final rankedEvidenceSet = SourceAwareLegacyEvidenceRanker.rank(
      combinedBatch.candidates,
      requestId: combinedBatch.requestId,
    );
    final candidatesById = {
      for (final candidate in combinedBatch.candidates)
        candidate.evidenceId: candidate,
    };
    final evidenceStartOffsets = <String, int>{};
    final evidenceEndOffsets = <String, int>{};

    // Keep the historical classic-index first-four cap and query/hit order.
    // Preserve the existing deterministic source order and selection limits.
    for (final evidenceId in rankedEvidenceSet.orderedEvidenceIds) {
      final hit = candidatesById[evidenceId]!;
      if (hit.retrievalMethod != 'CLASSIC_SUBSTRING_INDEX') continue;
      final isLecture = hit.asset != null;
      final articleNumber = RegExp(r'(?:条文|第)\s*(\d+)')
          .firstMatch(hit.title)
          ?.group(1);
      final sourcePath =
          hit.asset ?? "assets/guji/${hit.bookId ?? 'unknown'}.txt";
      evidenceStartOffsets[evidenceId] = buffer.length;
      buffer
        ..writeln('[App经典全文索引 · ${hit.sourceLabel} · ${hit.title}]')
        ..writeln(
          '资料类型：${isLecture ? '倪师讲稿/整理讲义（学习资料）' : 'App 古籍文本知识条目'}',
        )
        ..writeln('来源标识：${hit.sourceId}')
        ..writeln('知识库条目定位：${hit.localBacklink}')
        ..writeln('知识库条目定位可用：${hit.hasLocalBacklink ? 'YES' : 'NO'}')
        ..writeln('本地资料路径：$sourcePath');
      if (hit.chapterIndex != null) {
        buffer.writeln('内部章节序号：${hit.chapterIndex}');
      }
      if (articleNumber != null) {
        buffer.writeln('条文号：$articleNumber');
      }
      buffer.writeln('检索摘要：${hit.snippet}');
      if (isLecture) {
        buffer.writeln('资料类型说明：当前引用对象为 App 内课程讲稿/整理讲义知识条目。');
      } else {
        buffer.writeln('资料类型说明：当前引用对象为 App 内古籍文本知识条目。');
      }
      evidenceEndOffsets[evidenceId] = buffer.length;
    }

    // Keep Guji book metadata blocks even when all candidates are dropped by
    // the old two-chapter-per-book limit, exactly as the previous projection.
    for (final book in requestedGujiBooks) {
      if (failedGujiBookIds.contains(book.id)) {
        buffer.writeln('[App古籍库 · ${book.title}] 读取失败，状态 MISSING。');
        continue;
      }
      final keptEvidenceIds = rankedEvidenceSet.orderedEvidenceIds.where((id) {
        final candidate = candidatesById[id];
        return candidate?.retrievalMethod == 'GUIJI_CHAPTER_SUBSTRING_MATCH' &&
            candidate?.bookId == book.id;
      });
      buffer
        ..writeln('[App古籍库 · ${book.title} · ${book.author} · ${book.asset}]')
        ..writeln('书籍简介：${book.intro}');
      if (keptEvidenceIds.isEmpty) {
        buffer.writeln('没有匹配到章节正文；以下仅提供该书的基本信息，不作为正文引用。');
      }
      for (final evidenceId in keptEvidenceIds) {
        final candidate = candidatesById[evidenceId]!;
        evidenceStartOffsets[evidenceId] = buffer.length;
        buffer
          ..writeln('章节：${candidate.title}')
          ..writeln('知识库条目定位：${candidate.localBacklink}')
          ..writeln('来源标识：${candidate.sourceId}')
          ..writeln('条目内容摘录：${candidate.excerpt}');
        evidenceEndOffsets[evidenceId] = buffer.length;
      }
    }

    if (includeMedicalCases) {
      if (medicalCaseReadFailed) {
        buffer.writeln('[App医案库] 读取失败，状态 MISSING。');
      } else {
        final casesBySourceId = {
          for (final medicalCase in medicalCases ?? const <MedicalCase>[])
            'medical_case:${medicalCase.seq}': medicalCase,
        };
        final keptMedicalEvidenceIds =
            rankedEvidenceSet.orderedEvidenceIds.where((id) {
          return candidatesById[id]?.retrievalMethod ==
              'MEDICAL_CASE_NORMALIZED_TEXT_MATCH';
        });
        for (final evidenceId in keptMedicalEvidenceIds) {
          final candidate = candidatesById[evidenceId]!;
          final medicalCase = casesBySourceId[candidate.sourceId]!;
          final entryId = candidate.sourceId;
          final entryLocator = candidate.localBacklink;
          evidenceStartOffsets[evidenceId] = buffer.length;
          buffer
            ..writeln('[App医案库 · 条目 ${medicalCase.seq}]')
            ..writeln('知识库条目定位：$entryLocator')
            ..writeln('来源标识：$entryId')
            ..writeln('资料类型：App 医案库本地整理记录')
            ..writeln(
              '日期字段：${medicalCase.date.isEmpty ? 'MISSING' : medicalCase.date}',
            )
            ..writeln(
              '诊断字段：${medicalCase.diagnosis.isEmpty ? 'MISSING' : medicalCase.diagnosis}',
            )
            ..writeln(
              '病机字段：${medicalCase.mechanism.isEmpty ? 'MISSING' : medicalCase.mechanism}',
            )
            ..writeln(
              '方剂字段：${medicalCase.formula.isEmpty ? 'MISSING' : medicalCase.formula}',
            )
            ..writeln(
              '针灸字段：${medicalCase.acupuncture.isEmpty ? 'MISSING' : medicalCase.acupuncture}',
            )
            ..writeln(
              '治法字段：${medicalCase.method.isEmpty ? 'MISSING' : medicalCase.method}',
            )
            ..writeln(
              '结果字段：${medicalCase.result.isEmpty ? 'MISSING' : medicalCase.result}',
            )
            ..writeln(
              '使用边界：这是 App 知识库中的整理案例；可用于病例复盘和知识对照，引用时保留条目身份，不把条目未记载的信息补成病例事实。',
            );
          evidenceEndOffsets[evidenceId] = buffer.length;
        }
      }
    }

    final rawResult = buffer.toString();
    final leadingTrim = rawResult.length - rawResult.trimLeft().length;
    final result = rawResult.trim();
    final boundedResult = result.length <= maxContextCharacters
        ? result
        : result.substring(0, maxContextCharacters);
    final presentedEvidenceIds = <String>{};
    final budgetOmittedEvidenceIds = <String>[];
    final budgetTruncatedEvidenceIds = <String>[];
    for (final evidenceId in rankedEvidenceSet.orderedEvidenceIds) {
      final startOffset = evidenceStartOffsets[evidenceId];
      final endOffset = evidenceEndOffsets[evidenceId];
      if (startOffset == null || endOffset == null) {
        budgetOmittedEvidenceIds.add(evidenceId);
        continue;
      }
      final visibleStart = startOffset - leadingTrim;
      final visibleEnd = endOffset - leadingTrim;
      if (visibleEnd <= boundedResult.length) {
        presentedEvidenceIds.add(evidenceId);
      } else if (visibleStart < boundedResult.length) {
        budgetTruncatedEvidenceIds.add(evidenceId);
      } else {
        budgetOmittedEvidenceIds.add(evidenceId);
      }
    }
    final rankedEvidence = <AssistantKnowledgeEvidenceReference>[
      for (final evidenceId in rankedEvidenceSet.orderedEvidenceIds)
        if (presentedEvidenceIds.contains(evidenceId))
          AssistantKnowledgeEvidenceReference(
            evidenceId: evidenceId,
            sourceId: candidatesById[evidenceId]!.sourceId,
          ),
    ];

    final hasPresentationOmissions =
        budgetOmittedEvidenceIds.isNotEmpty ||
            budgetTruncatedEvidenceIds.isNotEmpty;
    final presentationRankedEvidenceSet = RankedEvidenceSet(
      requestId: rankedEvidenceSet.requestId,
      strategyId: rankedEvidenceSet.strategyId,
      strategyVersion: rankedEvidenceSet.strategyVersion,
      decisions: rankedEvidenceSet.decisions,
      orderedEvidenceIds: rankedEvidenceSet.orderedEvidenceIds,
      budget: EvidenceBudgetSnapshot(
        unit: EvidenceBudgetUnit.characters,
        limit: maxContextCharacters,
        used: boundedResult.length,
        applied: true,
        omittedEvidenceIds: budgetOmittedEvidenceIds,
        truncatedEvidenceIds: budgetTruncatedEvidenceIds,
      ),
      status: rankedEvidenceSet.orderedEvidenceIds.isEmpty
          ? RankedEvidenceSetStatus.noUsableEvidence
          : hasPresentationOmissions
              ? RankedEvidenceSetStatus.budgetTruncated
              : RankedEvidenceSetStatus.ranked,
      diagnostics: [
        ...rankedEvidenceSet.diagnostics,
        'CONTEXT_PRESENTATION_BUDGET_CHARACTERS_APPLIED',
        if (budgetOmittedEvidenceIds.isNotEmpty)
          'CONTEXT_PRESENTATION_EVIDENCE_OMITTED',
        if (budgetTruncatedEvidenceIds.isNotEmpty)
          'CONTEXT_PRESENTATION_EVIDENCE_TRUNCATED',
        'CONTEXT_BUDGET_USED_UTF16_CODE_UNITS',
      ],
    );
    return AssistantKnowledgeContextBuildResult(
      text: boundedResult,
      knownEvidenceIds: combinedBatch.candidates
          .map((candidate) => candidate.evidenceId)
          .toList(growable: false),
      rankedEvidence: rankedEvidence,
      rankedEvidenceSet: presentationRankedEvidenceSet,
    );
  }

  static String build(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return '';

    final terms = normalized
        .split(RegExp(r'[，。！？、；：,.!?;\s]+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .toSet();

    final allFormulas = FormulaRepository.getAll();
    final exactFormulaMatches = allFormulas.where((formula) {
      final names = [
        formula.name,
        ...formula.alias.split(',').map((value) => value.trim()),
      ].where((value) => value.isNotEmpty);
      return names.any((name) => normalized.contains(name));
    }).toList(growable: false);
    final formulaCandidates = exactFormulaMatches.isNotEmpty
        // An exact formula-name lookup is a focused request. Do not broaden it
        // to every other formula that happens to share one of its ingredients.
        ? exactFormulaMatches
        // Component-based expansion remains available for herb/component
        // queries where the user did not name a specific formula.
        : [
            ...allFormulas.where((formula) =>
                formula.keywords.any((keyword) => normalized.contains(keyword))),
            ...allFormulas.where((formula) =>
                formula.components.any(
                  (component) => normalized.contains(component.name),
                )),
          ];
    final formulas = <Formula>[];
    for (final formula in formulaCandidates) {
      if (!formulas.any((item) => item.id == formula.id)) {
        formulas.add(formula);
      }
      if (formulas.length >= maxFormulaEntries) break;
    }

    final herbs = HerbRepository.getAll().where((herb) {
      if (normalized.contains(herb.name)) return true;
      if (HerbRepository.aliasNames.any((alias) =>
          normalized.contains(alias) &&
          HerbRepository.canonicalOf(alias) == herb.name)) {
        return true;
      }
      return terms.any((term) => HerbRepository.matchesQuery(herb, term));
    }).take(maxHerbEntries).toList(growable: false);

    final acupuncture =
        <({String categoryId, AcupointEntry entry})>[];
    for (final category in AcupunctureRepository.getAll()) {
      for (final entry in category.entries) {
        final matches = normalized.contains(entry.symptom) ||
            entry.aliases.any(normalized.contains) ||
            terms.any((term) =>
                entry.symptom.contains(term) ||
                entry.aliases.any((alias) => alias.contains(term)));
        if (matches &&
            !acupuncture.any((item) =>
                item.categoryId == category.id && item.entry.id == entry.id)) {
          acupuncture.add((categoryId: category.id, entry: entry));
        }
        if (acupuncture.length >= maxAcupunctureEntries) break;
      }
      if (acupuncture.length >= maxAcupunctureEntries) break;
    }

    final acupoints = <AcupointDetail>[];
    for (final point in AcupointRepository.getAll()) {
      final matches = normalized.contains(point.name) ||
          terms.any((term) =>
              point.name.contains(term) ||
              point.meridian.contains(term) ||
              point.description.contains(term) ||
              point.location.contains(term) ||
              point.clinicalNotes.contains(term));
      if (matches && !acupoints.any((item) => item.name == point.name)) {
        acupoints.add(point);
      }
      if (acupoints.length >= maxAcupointEntries) break;
    }

    final neijing = kNeijingEntries.where((entry) {
      return normalized.contains(entry.title) ||
          normalized.contains(entry.source) ||
          terms.any((term) =>
              entry.title.contains(term) ||
              entry.source.contains(term) ||
              entry.original.contains(term) ||
              entry.tags.any((tag) => tag.contains(term)));
    }).take(maxNeijingEntries).toList(growable: false);

    if (formulas.isEmpty &&
        herbs.isEmpty &&
        acupuncture.isEmpty &&
        acupoints.isEmpty &&
        neijing.isEmpty) {
      return '';
    }

    final buffer = StringBuffer()
      ..writeln('以下内容来自 App 内置知识库，应按资料类型、条目定位和来源标识核对。')
      ..writeln('可据此解释辨病辨证依据、病机、治法、方剂和针灸思路；具体问诊结果的诊断解释须同时对应 App 已校验业务结果与可追溯知识条目，一般知识讲解以知识条目为依据。')
      ..writeln('不得补造未返回字段；保留资料类型、知识库条目定位和 sourceId，无法定位或检索无命中时标记 MISSING。');

    for (final formula in formulas) {
      buffer
        ..writeln('[App方剂库 assets/data/formulas.json · ${formula.id}]')
        ..writeln('来源标识：formula:${formula.id}')
        ..writeln('知识库条目定位：assets/data/formulas.json#id=${formula.id}')
        ..writeln('方名：${formula.name}')
        ..writeln('别名：${formula.alias}')
        ..writeln('归经/分类：${formula.meridian} / ${formula.category}')
        ..writeln('原始适应证字段：${formula.indication}')
        ..writeln('原始解释字段：${formula.explanation}')
        ..writeln('组成药名：${formula.components.map((item) => item.name).join('、')}');
      if (formula.contraindication.trim().isNotEmpty) {
        buffer.writeln('原始禁忌字段：${formula.contraindication}');
      }
    }

    for (final herb in herbs) {
      buffer
        ..writeln('[App本草库 assets/data/herbs.json · ${herb.name}]')
        ..writeln('来源标识：herb:${herb.name}')
        ..writeln('知识库条目定位：assets/data/herbs.json#name=${herb.name}')
        ..writeln('药名：${herb.name}')
        ..writeln('性味：${herb.nature ?? 'MISSING'}；${herb.flavor}')
        ..writeln('归经字段：${herb.meridians.join('、')}')
        ..writeln('功用字段：${herb.action ?? 'MISSING'}');
      if ((herb.contraindication ?? '').trim().isNotEmpty) {
        buffer.writeln('原始禁忌字段：${herb.contraindication!}');
      }
      if ((herb.historicalNotes ?? '').trim().isNotEmpty) {
        buffer.writeln('历史备注字段：${herb.historicalNotes!}');
      }
    }

    for (final hit in acupuncture) {
      final entry = hit.entry;
      final sourceId = 'acupuncture:${hit.categoryId}:${entry.id}';
      buffer
        ..writeln('[App针灸处方库 assets/data/acupuncture.json · ${hit.categoryId}/entry:${entry.id}]')
        ..writeln('来源标识：$sourceId')
        ..writeln('知识库条目定位：assets/data/acupuncture.json#category=${hit.categoryId}&id=${entry.id}')
        ..writeln('主诉/病症：${entry.symptom}')
        ..writeln('别名：${entry.aliases.join('、')}')
        ..writeln('穴位与操作：${entry.acupointsText}')
        ..writeln('原始备注：${entry.notes.isEmpty ? 'MISSING' : entry.notes}')
        ..writeln('医案字段：${entry.medicalCase.isEmpty ? 'MISSING' : entry.medicalCase}')
        ..writeln('数据来源标签：${entry.sourceLabel}');
    }

    for (final point in acupoints) {
      buffer
        ..writeln('[App穴位库 assets/data/acupoints.json · ${point.name}]')
        ..writeln('来源标识：acupoint:${point.name}')
        ..writeln('知识库条目定位：assets/data/acupoints.json#name=${point.name}')
        ..writeln('穴名：${point.name}；经络：${point.meridian}；特定穴属性：${point.attribute}')
        ..writeln('定位：${point.location.isEmpty ? 'MISSING' : point.location}')
        ..writeln('针刺：${point.needling.isEmpty ? 'MISSING' : point.needling}')
        ..writeln('艾灸：${point.moxibustion.isEmpty ? 'MISSING' : point.moxibustion}')
        ..writeln('禁忌：${point.contraindication.isEmpty ? 'MISSING' : point.contraindication}')
        ..writeln('临床备注：${point.clinicalNotes.isEmpty ? 'MISSING' : point.clinicalNotes}');
    }

    for (final entry in neijing) {
      buffer
        ..writeln('[App内经结构化条目 lib/data/neijing_entries.dart · ${entry.id}]')
        ..writeln('来源标识：neijing:${entry.id}')
        ..writeln('知识库条目定位：lib/data/neijing_entries.dart#id=${entry.id}')
        ..writeln('维度：${entry.dimension}；标题：${entry.title}')
        ..writeln('原文摘录：${entry.original}')
        ..writeln('条目所载出处：${entry.source}')
        ..writeln('白话整理：${entry.vernacular}')
        ..writeln('倪师解读：${entry.nishi}');
    }

    final result = buffer.toString().trim();
    if (result.length <= maxContextCharacters) return result;
    return result.substring(0, maxContextCharacters);
  }
}
