import '../data/acupuncture_repository.dart';
import '../data/acupoint_repository.dart';
import '../data/formula_repository.dart';
import '../data/guji_data.dart';
import '../data/medical_case_data.dart';
import 'classic_search_service.dart';
import '../data/herb_repository.dart';
import '../data/neijing_entries.dart';
import '../models/formula.dart';
import '../models/acupuncture.dart';
import '../models/acupoint_detail.dart';


/// A source that was actually resolved from the bundled classic-text index.
/// A local backlink is not a verified printed-edition/page citation.
class AssistantKnowledgeSourceReference {
  const AssistantKnowledgeSourceReference({
    required this.sourceId,
    required this.sourceLabel,
    required this.title,
    required this.localBacklink,
    required this.locatorStatus,
    this.sourceKind = 'classic_text',
    this.sourceVerificationStatus = 'UNKNOWN',
    this.bibliographicLocatorVerified = false,
  });

  final String sourceId;
  final String sourceLabel;
  final String title;
  final String localBacklink;
  final String locatorStatus;
  final String sourceKind;
  final String sourceVerificationStatus;
  final bool bibliographicLocatorVerified;

  String toCitationText() {
    final backlinkStatus = localBacklink == 'MISSING' ? 'MISSING' : 'AVAILABLE';
    if (sourceKind == 'lecture') {
      return '- $sourceLabel｜$title\n'
          '  资料类型：课程讲稿/整理讲义（学习资料）\n'
          '  本地回链：$localBacklink（$backlinkStatus）\n'
          '  来源标识：$sourceId\n'
          '  使用边界：讲稿用于学习内容检索；其中引用的古籍文字不自动等同于已核验的指定版本原文。';
    }
    if (sourceKind == 'classic_text') {
      return '- $sourceLabel｜$title\n'
          '  来源类型：App 古籍文本资产\n'
          '  原文来源核验状态：$sourceVerificationStatus\n'
          '  本地回链：$localBacklink（$backlinkStatus）\n'
          '  版本/卷页定位：$locatorStatus；未核验时不声明具体版本或页码。\n'
          '  来源标识：$sourceId';
    }
    if (sourceKind == 'medical_case') {
      return '- $sourceLabel｜$title\n'
          '  来源类型：$sourceKind\n'
          '  原文来源核验状态：$sourceVerificationStatus\n'
          '  本地回链：$localBacklink（$backlinkStatus）\n'
          '  书目定位状态：$locatorStatus；纸本版本/卷页：'
          '${bibliographicLocatorVerified ? 'VERIFIED' : 'MISSING'}'
          '${bibliographicLocatorVerified ? '' : '（尚未完成纸本/影印本核验）'}\n'
          '  来源标识：$sourceId';
    }
    return '- $sourceLabel｜$title\n'
        '  App 数据类型：$sourceKind\n'
        '  本地回链：$localBacklink（$backlinkStatus）\n'
        '  来源标识：$sourceId';
  }
}

enum AssistantKnowledgeRetrievalStatus { noResults, retrieved, partial, failed }


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
  });

  final String text;
  final List<AssistantKnowledgeSourceReference> sources;
  final AssistantKnowledgeRetrievalStatus status;
  final String? failureMessage;

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
      : '\n\n参考来源（App 本地检索；不代表纸本版本校勘完成）：\n' +
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
    late final String text;
    try {
      text = await buildAsync(
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
    if (text.isEmpty) {
      return const AssistantKnowledgeContextResult(
        text: '',
        status: AssistantKnowledgeRetrievalStatus.noResults,
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
              locatorStatus: 'MISSING',
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
              locatorStatus: 'MISSING',
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
                locatorStatus: 'MISSING',
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
              locatorStatus: 'MISSING',
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
              locatorStatus: 'MISSING',
              sourceKind: 'neijing',
            ));
          }
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
          final ledger = matchedCase.sourceLedger;
          sources.add(AssistantKnowledgeSourceReference(
            sourceId: sourceId,
            sourceLabel: 'App 医案库',
            title: matchedCase.displayName,
            localBacklink: 'medical_case:internal-seq:$sequence',
            locatorStatus: ledger.status,
            sourceKind: 'medical_case',
            sourceVerificationStatus: ledger.sourceStatus,
            bibliographicLocatorVerified: ledger.isVerified,
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
          locatorStatus: hit.locatorStatus,
          sourceKind: hit.asset != null ? 'lecture' : 'classic_text',
          bibliographicLocatorVerified: hit.hasVerifiedBibliographicLocator,
        ));
      } catch (_) {
        // A failed reverse lookup is not a citation. Keep the retrieval text,
        // but do not persist an unresolvable source identifier.
      }
    }
    final status = sources.isEmpty || sources.length < sourceIds.length
        ? AssistantKnowledgeRetrievalStatus.partial
        : AssistantKnowledgeRetrievalStatus.retrieved;
    return AssistantKnowledgeContextResult(
      text: text,
      sources: List.unmodifiable(sources),
      status: status,
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

  /// Extends the fast in-memory retrieval with the bundled classical-text and
  /// medical-case libraries. Case excerpts carry an explicit provenance warning:
  /// the local table sequence is not a primary-source locator.
  static Future<String> buildAsync(
    String query, {
    bool includeMedicalCases = true,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return '';
    final base = build(normalized);
    if (!shouldRetrieveForQuery(normalized)) return base;
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

    final classicQueries = deriveClassicQueries(normalized)
        .map((provenance) => provenance.query);

    final classicHits = <ClassicHit>[];
    try {
      for (final searchQuery in classicQueries) {
        if (searchQuery.trim().length < 2) continue;
        final result = await ClassicSearchService.search(searchQuery);
        for (final hit in result.hits) {
          final identity = '${hit.source}|${hit.asset ?? hit.bookId}|${hit.chapterIndex}|${hit.title}';
          if (classicHits.any((item) =>
              '${item.source}|${item.asset ?? item.bookId}|${item.chapterIndex}|${item.title}' ==
              identity)) {
            continue;
          }
          classicHits.add(hit);
          if (classicHits.length >= 4) break;
        }
        if (classicHits.length >= 4) break;
      }
    } catch (_) {
      buffer.writeln('[App经典全文索引] 索引读取失败，状态 MISSING。');
    }

    for (final hit in classicHits) {
      final isLecture = hit.asset != null;
      final articleNumber = RegExp(r'(?:条文|第)\s*(\d+)').firstMatch(hit.title)?.group(1);
      final sourcePath = hit.asset ?? "assets/guji/${hit.bookId ?? 'unknown'}.txt";
      buffer
        ..writeln('[App经典全文索引 · ${hit.sourceLabel} · ${hit.title}]')
        ..writeln('资料类型：${isLecture ? '倪师讲稿/整理讲义（学习资料）' : 'App 古籍文本资产'}')
        ..writeln('来源标识：${hit.sourceId}')
        ..writeln('本地回链：${hit.localBacklink}')
        ..writeln('本地回链标识可用：${hit.hasLocalBacklink ? 'YES' : 'NO'}')
        ..writeln('本地来源：$sourcePath')
        ..writeln('内部章节序号：${hit.chapterIndex?.toString() ?? 'MISSING'}')
        ..writeln('条文号：${articleNumber ?? 'MISSING'}（仅从标题显式提取，不由内部文件序号推断）')
        ..writeln('检索摘要：${hit.snippet}');
      if (isLecture) {
        buffer
          ..writeln('来源说明：当前实际来源是 App 内的课程讲稿/整理讲义；原始录音、具体讲次和版本未在该资料条目中登记。')
          ..writeln('使用限制：可用于学习和知识解释；讲稿中引用的古籍文字未逐条核对指定版本，不得冒充已校勘的仲景原文，也不得作为诊断规则的唯一来源。');
      } else {
        buffer
          ..writeln('版本/底本/卷页：${hit.hasVerifiedBibliographicLocator ? 'VERIFIED' : 'MISSING'}')
          ..writeln('使用限制：这是 App 内古籍文本资产；未核验版本、卷页和异文时，不声明特定版本或已完成校勘。');
      }
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

    for (final book in requestedGujiBooks) {
      try {
        final chapters = await GujiRepository.chaptersOf(book);
        final hits = chapters.where((chapter) {
          return terms.any((term) =>
              chapter.title.contains(term) || chapter.body.contains(term));
        }).take(2).toList(growable: false);
        buffer
          ..writeln('[App古籍库 · ${book.title} · ${book.author} · ${book.asset}]')
          ..writeln('书籍简介：${book.intro}');
        if (hits.isEmpty) {
          buffer.writeln('章节正文匹配：MISSING；仅返回书目元数据，未命中可引用章节。');
        }
        for (final chapter in hits) {
          final excerpt = chapter.body.length > 1400
              ? chapter.body.substring(0, 1400)
              : chapter.body;
          buffer
            ..writeln('章节：${chapter.title}')
            ..writeln('原文摘录（本地公版文本资产，版本/页码仍需另行校核）：$excerpt');
        }
      } catch (_) {
        buffer.writeln('[App古籍库 · ${book.title}] 读取失败，状态 MISSING。');
      }
    }

    if (includeMedicalCases) {
      try {
        final cases = await getAllMedicalCases();
        final hits = cases
            .where((medicalCase) => terms.any(medicalCase.matches))
            .take(2)
            .toList(growable: false);
        for (final medicalCase in hits) {
          final ledger = medicalCase.sourceLedger;
          final verifiedLocator = ledger.isVerified
              ? [
                  ledger.sourceTitle,
                  ledger.edition,
                  ledger.volume,
                  ledger.page,
                  ledger.passage,
                ].join(' · ')
              : 'MISSING（原文来源核验状态：${ledger.sourceStatus}；网页 URL 不等于纸本版本、卷次和页码；内部序号不是原始病例页码或稳定来源 ID，也不是原始来源定位）';
          buffer
            ..writeln('[App医案库 assets/medical_cases/cases_table.md · 内部序号 ${medicalCase.seq}]')
            ..writeln('日期字段：${medicalCase.date.isEmpty ? 'MISSING' : medicalCase.date}')
            ..writeln('诊断字段：${medicalCase.diagnosis.isEmpty ? 'MISSING' : medicalCase.diagnosis}')
            ..writeln('病机字段：${medicalCase.mechanism.isEmpty ? 'MISSING' : medicalCase.mechanism}')
            ..writeln('方剂字段：${medicalCase.formula.isEmpty ? 'MISSING' : medicalCase.formula}')
            ..writeln('针灸字段：${medicalCase.acupuncture.isEmpty ? 'MISSING' : medicalCase.acupuncture}')
            ..writeln('治法字段：${medicalCase.method.isEmpty ? 'MISSING' : medicalCase.method}')
            ..writeln('结果字段：${medicalCase.result.isEmpty ? 'MISSING' : medicalCase.result}')
            ..writeln('来源标识：medical_case:${medicalCase.seq}')
            ..writeln('本地回链：medical_case:internal-seq:${medicalCase.seq}')
            ..writeln('原文来源核验状态：${ledger.sourceStatus}')
            ..writeln('纸本定位核验状态：${ledger.status}')
            ..writeln('来源定位：$verifiedLocator')
            ..writeln('来源账本：')
            ..writeln(ledger.toDisplayText())
            ..writeln('使用限制：仅作为本地整理记录检索；只有纸本定位状态为 VERIFIED 且纸本定位字段完整时，才允许将账本定位作为已核验出处；网页原文核验不代表纸本版本、卷次或页码已核验；病例内容本身不构成疗效证据。');
        }
      } catch (_) {
        buffer.writeln('[App医案库] 读取失败，状态 MISSING。');
      }
    }

    final result = buffer.toString().trim();
    if (result.length <= maxContextCharacters) return result;
    return result.substring(0, maxContextCharacters);
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
      ..writeln('以下内容来自 App 内置数据，仅作为可核对的参考资料。')
      ..writeln('不得把条目描述改写成对用户的诊断、处方或剂量建议。')
      ..writeln('原文、整理解释和倪师讲授字段必须按各自标签区分；缺少出处时标记 MISSING。');

    for (final formula in formulas) {
      buffer
        ..writeln('[App方剂库 assets/data/formulas.json · ${formula.id}]')
        ..writeln('来源标识：formula:${formula.id}')
        ..writeln('本地回链：assets/data/formulas.json#id=${formula.id}')
        ..writeln('来源定位状态：MISSING（数据资产路径不等同于古籍版本/卷页核验）')
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
        ..writeln('本地回链：assets/data/herbs.json#name=${herb.name}')
        ..writeln('来源定位状态：MISSING（数据资产路径不等同于古籍版本/卷页核验）')
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
        ..writeln('本地回链：assets/data/acupuncture.json#category=${hit.categoryId}&id=${entry.id}')
        ..writeln('来源定位状态：MISSING（本地分类/条目 ID 不等同于原始文献定位）')
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
        ..writeln('本地回链：assets/data/acupoints.json#name=${point.name}')
        ..writeln('来源定位状态：MISSING（数据资产路径不等同于古籍版本/卷页核验）')
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
        ..writeln('本地回链：lib/data/neijing_entries.dart#id=${entry.id}')
        ..writeln('来源定位状态：MISSING（条目所载篇章仍需对照指定版本核验）')
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
