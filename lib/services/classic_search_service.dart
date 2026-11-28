import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/guji_data.dart';
import '../data/yijing_lecture_data.dart';
import '../data/minggua_data.dart';
import 'gzip_codec_stub.dart' if (dart.library.io) 'gzip_codec_io.dart';

/// 经典（讲稿 + 古籍原文）全文检索。
///
/// 索引是构建期产物 `assets/guji/classic_index.json.gz`
/// （生成脚本 `tool/build_classic_search_index.py`），覆盖：
/// fork 主索引包含伤寒、金匮、内经讲稿与古籍原文《灵枢》《针灸大成》；
/// supplemental 索引按文件级白名单追加上游独有经典条文、六经附录及本草讲稿 335 篇。
///
/// ⚠️ 讲稿或古书有增删改后必须重跑脚本，否则搜索漏内容。
class ClassicHit {
  /// shanghan / jingui / neijing / bencao / guji
  final String source;

  /// 展示用来源名（如「伤寒论讲稿」「针灸大成」）。
  final String sourceLabel;

  final String title;

  /// 讲稿条目对应的 markdown 资产（古籍原文为 null）。
  final String? asset;

  /// 古籍原文书名 id 与章节序号（讲稿为 null）。
  final String? bookId;
  final int? chapterIndex;

  /// 命中位置的上下文摘要。
  final String snippet;

  const ClassicHit({
    required this.source,
    required this.sourceLabel,
    required this.title,
    required this.snippet,
    this.asset,
    this.bookId,
    this.chapterIndex,
  });

  /// Stable retrieval identity for reopening this entry inside the App.
  String get sourceId {
    if (asset != null && asset!.trim().isNotEmpty) {
      return '$source:$asset';
    }
    if (bookId != null &&
        bookId!.trim().isNotEmpty &&
        chapterIndex != null &&
        chapterIndex! >= 0) {
      return '$source:$bookId:$chapterIndex';
    }
    return 'MISSING';
  }

  /// Local App destination for this hit, or MISSING when unavailable.
  String get localBacklink => asset != null
      ? asset!
      : bookId != null
          ? 'guji:$bookId#chapter:${chapterIndex ?? 'MISSING'}'
          : 'MISSING';

  /// Whether the App can reopen the selected local entry.
  bool get hasLocalBacklink =>
      (asset != null && asset!.trim().isNotEmpty) ||
      (bookId != null &&
          bookId!.trim().isNotEmpty &&
          chapterIndex != null &&
          chapterIndex! >= 0);
}


/// Exact asset-backed reader destination for assistant citations. The source ID
/// is a reader module ID plus an exact asset path; display titles are never
/// used as lookup keys.
class ClassicReaderAsset {
  final String moduleId;
  final String title;
  final String asset;

  const ClassicReaderAsset({
    required this.moduleId,
    required this.title,
    required this.asset,
  });
}

class ClassicSearchResult {
  /// 命中总数（[hits] 只保留前若干条用于展示）。
  final int total;
  final List<ClassicHit> hits;

  const ClassicSearchResult({required this.total, required this.hits});

  static const ClassicSearchResult empty =
      ClassicSearchResult(total: 0, hits: []);
}

class _IndexEntry {
  final String source;
  final String title;
  final String? asset;
  final String? bookId;
  final int? chapterIndex;
  final String text;

  const _IndexEntry({
    required this.source,
    required this.title,
    required this.text,
    this.asset,
    this.bookId,
    this.chapterIndex,
  });
}

class ClassicSearchService {
  static const String assetPath = 'assets/guji/classic_index.json.gz';

  /// 展示条数上限（命中总数另外统计）。
  static const int maxHits = 40;

  static List<_IndexEntry>? _entries;
  static Future<void>? _loading;

  /// 索引是否已加载（供 UI 判断是否显示加载态）。
  static bool get isLoaded => _entries != null;

  static const Map<String, String> _sourceLabels = {
    'shanghan': '伤寒论讲稿',
    'jingui': '金匮要略讲稿',
    'neijing': '内经讲稿',
    'zhenjiu': '针灸讲稿',
    'bencao': '本草讲稿',
  };

  /// Maps a classic index source to the module ID used by reader selections.
  /// Keep this allowlist beside reverse source resolution so search and
  /// assistant citation navigation cannot drift independently.
  static String? contextualModuleIdForSource(String source) {
    switch (source) {
      case 'shanghan':
        return 'shanghan';
      case 'jingui':
        return 'jingui';
      case 'neijing':
        return 'neijing-reading';
      case 'zhenjiu':
        return 'zhenjiu-reading';
      case 'bencao':
        return 'bencao-reading';
      default:
        return null;
    }
  }

  /// Reader modules whose Markdown asset IDs have a verified paragraph
  /// source contract. Guji is deliberately excluded because it uses an
  /// independently verified original-TXT line map.
  static const Map<String, String> _assetReaderModulePrefixes = {
    'shanghan': 'assets/shanghan/',
    'jingui': 'assets/jingui/',
    'neijing-reading': 'assets/neijing/',
    'zhenjiu-reading': 'assets/zhenjiu_lecture/',
    'bencao-reading': 'assets/bencao_lecture/',
    'yijing-reading': 'assets/yijing/',
    'minggua-reading': 'assets/yijing_minggua/',
  };

  /// The single canonical anchor builder for asset-backed reader modules.
  /// Search results, library pages and assistant backlinks must all call this
  /// method rather than concatenate module/asset strings independently.
  static String? contextualAnchorIdForReaderAsset({
    required String moduleId,
    required String asset,
  }) {
    final normalizedModuleId = moduleId.trim();
    final normalizedAsset = asset.trim();
    final requiredPrefix = _assetReaderModulePrefixes[normalizedModuleId];
    if (requiredPrefix == null ||
        !normalizedAsset.startsWith(requiredPrefix) ||
        !normalizedAsset.endsWith('.md') ||
        normalizedAsset.contains('..') ||
        normalizedAsset.contains(r'\')) {
      return null;
    }
    // The local first asset represents the second numbered clause in the
    // lecture's established source contract. Keep this exception centralized.
    if (normalizedModuleId == 'shanghan' &&
        normalizedAsset == 'assets/shanghan/clause_001.md') {
      return 'shanghan:clause:002';
    }
    return '$normalizedModuleId:passage:$normalizedAsset';
  }

  /// Returns the stable reader passage anchor for one indexed lecture.
  /// Sources without an explicit reader contract remain non-contextual.
  static String? contextualAnchorIdForHit(ClassicHit hit) {
    final moduleId = contextualModuleIdForSource(hit.source);
    final asset = hit.asset?.trim();
    if (moduleId == null || asset == null || asset.isEmpty) return null;
    return contextualAnchorIdForReaderAsset(
      moduleId: moduleId,
      asset: asset,
    );
  }

  /// Resolve Yijing and Minggua reader citations through their source
  /// manifests. These module IDs intentionally differ from classic index
  /// source keys and are not part of the compressed Guji search index.
  /// Exact asset membership is required; titles and fuzzy matching are banned.
  static ClassicReaderAsset? findReaderAssetBySourceId(String sourceId) {
    for (final lecture in kYiJingLectures) {
      final expected = 'yijing-reading:${lecture.asset}';
      if (sourceId == expected) {
        return ClassicReaderAsset(
          moduleId: 'yijing-reading',
          title: '倪师《天纪·人间道》·${lecture.name}',
          asset: lecture.asset,
        );
      }
    }
    for (final entry in kMingGuaEntries) {
      final expected = 'minggua-reading:${entry.asset}';
      if (sourceId == expected) {
        return ClassicReaderAsset(
          moduleId: 'minggua-reading',
          title: '倪师《天纪·四柱命卦》·${entry.title}',
          asset: entry.asset,
        );
      }
    }
    return null;
  }

  static String? _indexedSourceForReaderModule(String moduleId) {
    switch (moduleId) {
      case 'neijing-reading':
        return 'neijing';
      case 'zhenjiu-reading':
        return 'zhenjiu';
      case 'bencao-reading':
        return 'bencao';
      default:
        return null;
    }
  }

  static String _labelOf(String source, String? bookId) {
    if (source == 'guji') {
      for (final b in kGujiBooks) {
        if (b.id == bookId) return b.title;
      }
      return '古籍原文';
    }
    return _sourceLabels[source] ?? source;
  }

  /// 首次调用解压并解析索引（约 1.8MB gzip → 5MB 文本），之后走内存缓存。
  static Future<void> ensureLoaded() async {
    if (_entries != null) return;
    _loading ??= _load();
    try {
      await _loading;
    } catch (_) {
      // 只在仍然指向本次失败的 future 时清除，允许下一次 ensureLoaded 重试，
      // 避免加载失败后索引永久不可用。
      _loading = null;
      rethrow;
    }
  }

  static Future<void> _load() async {
    final data = await rootBundle.load(assetPath);
    final bytes = gunzipBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final list = (decoded['entries'] as List<dynamic>).cast<Map<String, dynamic>>();
    final entries = <_IndexEntry>[
      for (final e in list)
        _IndexEntry(
          source: e['s'] as String,
          title: (e['t'] as String?) ?? '',
          asset: e['a'] as String?,
          bookId: e['b'] as String?,
          chapterIndex: e['i'] as int?,
          text: (e['x'] as String?) ?? '',
        ),
    ];

    // Keep the fork's existing classic index as the primary source. The
    // supplemental upstream index is filtered to genuinely missing asset
    // paths only; same-path upstream rewrites must never shadow local content.
    final supplemental = await rootBundle.load(
      'assets/guji/upstream_increment_index.json.gz',
    );
    final supplementalBytes = gunzipBytes(
      supplemental.buffer.asUint8List(
        supplemental.offsetInBytes,
        supplemental.lengthInBytes,
      ),
    );
    final supplementalDecoded =
        jsonDecode(utf8.decode(supplementalBytes)) as Map<String, dynamic>;
    final supplementalList = (supplementalDecoded['entries'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    const supplementalShanghanAssets = <String>{
      'assets/shanghan/clause_380.md',
      'assets/shanghan/clause_381.md',
      'assets/shanghan/clause_382.md',
      'assets/shanghan/clause_383.md',
      'assets/shanghan/clause_384.md',
      'assets/shanghan/clause_385.md',
      'assets/shanghan/clause_386.md',
      'assets/shanghan/clause_387.md',
      'assets/shanghan/clause_388.md',
      'assets/shanghan/clause_389.md',
      'assets/shanghan/clause_390.md',
      'assets/shanghan/clause_176_upstream.md',
      'assets/shanghan/appendix_001_六经辨证总结.md',
      'assets/shanghan/appendix_002_六经传变规律.md',
      'assets/shanghan/appendix_003_六经病欲解时.md',
      'assets/shanghan/appendix_004_六经辨证临床要点.md',
    };
    const supplementalJinguiAssets = <String>{
      'assets/jingui/clause_453.md',
      'assets/jingui/clause_454.md',
    };
    final indexedAssetKeys = entries
        .where((entry) => entry.asset != null)
        .map((entry) => '${entry.source}:${entry.asset}')
        .toSet();
    for (final e in supplementalList) {
      final source = e['s'] as String?;
      final indexedAsset = e['a'] as String?;
      // Upstream clause_176.md conflicts with the fork's local clause_176.md
      // (which contains a different lecture article). Keep the upstream article
      // as an explicitly named parallel reading asset rather than overwrite it.
      final asset = indexedAsset == 'assets/shanghan/clause_176.md'
          ? 'assets/shanghan/clause_176_upstream.md'
          : indexedAsset;
      final isMissingPath =
          (source == 'shanghan' && asset != null &&
              supplementalShanghanAssets.contains(asset)) ||
          (source == 'jingui' && asset != null &&
              supplementalJinguiAssets.contains(asset)) ||
          (source == 'bencao' &&
              asset != null &&
              asset.startsWith('assets/bencao_lecture/') &&
              asset.endsWith('.md'));
      final key = source != null && asset != null ? '$source:$asset' : '';
      if (!isMissingPath || indexedAssetKeys.contains(key)) continue;
      entries.add(
        _IndexEntry(
          source: source!,
          title: (e['t'] as String?) ?? '',
          asset: asset,
          bookId: e['b'] as String?,
          chapterIndex: e['i'] as int?,
          text: (e['x'] as String?) ?? '',
        ),
      );
      indexedAssetKeys.add(key);
    }
    _entries = entries;
  }

  /// Resolve a previously emitted local source ID back to the indexed hit.
  /// This is the reverse side of the retrieval backlink; unknown or MISSING
  /// identifiers return null instead of falling back to a fuzzy search.
  static Future<ClassicHit?> findBySourceId(String sourceId) async {
    final normalized = sourceId.trim();
    if (normalized.isEmpty || normalized == 'MISSING') return null;
    await ensureLoaded();
    for (final entry in _entries!) {
      final hit = ClassicHit(
        source: entry.source,
        sourceLabel: _labelOf(entry.source, entry.bookId),
        title: entry.title,
        asset: entry.asset,
        bookId: entry.bookId,
        chapterIndex: entry.chapterIndex,
        snippet: _snippet(entry.text, -1, 0),
      );
      if (_matchesSourceId(hit, normalized)) return hit;
    }
    return null;
  }

  /// Accept canonical IDs and the one persisted legacy shape:
  /// source:asset-or-bookId:chapterIndex-or-MISSING:title.
  ///
  /// Legacy title text is ignored as identity, but its position and field count
  /// are fixed. Do not accept arbitrary trailing segments: a citation with a
  /// forged paragraph/asset suffix must not be rebound to an indexed entry.
  /// Reader-module aliases are accepted only through the explicit allowlist.
  static bool _matchesSourceId(ClassicHit hit, String candidate) {
    if (hit.sourceId == candidate) return true;
    final parts = candidate.split(':');

    if (hit.asset != null && hit.asset!.trim().isNotEmpty) {
      final source = _indexedSourceForReaderModule(parts.first) ?? parts.first;
      if (parts.length == 2) {
        // The only current reader-module alias form is <moduleId>:<asset>.
        return source == hit.source && parts[1] == hit.asset;
      }
      if (parts.length != 4) return false;
      final legacyChapterIndex = hit.chapterIndex?.toString() ?? 'MISSING';
      return source == hit.source &&
          parts[1] == hit.asset &&
          parts[2] == legacyChapterIndex &&
          parts[3].trim().isNotEmpty;
    }

    if (hit.bookId != null &&
        hit.chapterIndex != null &&
        hit.chapterIndex! >= 0) {
      return parts.length == 4 &&
          parts[0] == hit.source &&
          parts[1] == hit.bookId &&
          parts[2] == hit.chapterIndex.toString() &&
          parts[3].trim().isNotEmpty;
    }
    return false;
  }

  /// 检索：标题命中优先，其次正文命中；正文命中给出关键词上下文摘要。
  static Future<ClassicSearchResult> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return ClassicSearchResult.empty;
    await ensureLoaded();
    final entries = _entries!;
    final needle = q.toLowerCase();

    final titleHits = <ClassicHit>[];
    final bodyHits = <ClassicHit>[];
    var total = 0;

    for (final e in entries) {
      final inTitle = e.title.toLowerCase().contains(needle);
      final idx = e.text.toLowerCase().indexOf(needle);
      if (!inTitle && idx < 0) continue;
      total++;
      if (titleHits.length + bodyHits.length >= maxHits) continue;
      final hit = ClassicHit(
        source: e.source,
        sourceLabel: _labelOf(e.source, e.bookId),
        title: e.title,
        asset: e.asset,
        bookId: e.bookId,
        chapterIndex: e.chapterIndex,
        snippet: _snippet(e.text, inTitle ? -1 : idx, q.length),
      );
      if (inTitle) {
        titleHits.add(hit);
      } else {
        bodyHits.add(hit);
      }
    }

    return ClassicSearchResult(
      total: total,
      hits: [...titleHits, ...bodyHits],
    );
  }

  /// 取命中位置前后各 32 字做摘要；[idx] < 0 表示只在标题命中，取正文开头。
  static String _snippet(String text, int idx, int queryLength) {
    const span = 32;
    if (text.isEmpty) return '';
    final start = idx < 0 ? 0 : (idx - span).clamp(0, text.length);
    final end = idx < 0
        ? (span * 2).clamp(0, text.length)
        : (idx + queryLength + span).clamp(0, text.length);
    final raw = text.substring(start, end).replaceAll('\n', ' ').trim();
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix$raw$suffix';
  }
}
