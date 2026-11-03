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

/// Bounded keyword retrieval from the app's bundled TCM knowledge data.
/// Returns source-labelled excerpts, never a diagnosis or prescription.
class AssistantKnowledgeContextBuilder {
  static const int maxContextCharacters = 6500;
  static const int maxFormulaEntries = 4;
  static const int maxHerbEntries = 5;
  static const int maxAcupunctureEntries = 3;
  static const int maxAcupointEntries = 3;
  static const int maxNeijingEntries = 3;

  /// Extends the fast in-memory retrieval with the bundled classical-text and
  /// medical-case libraries. Case excerpts carry an explicit provenance warning:
  /// the local table sequence is not a primary-source locator.
  static Future<String> buildAsync(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return '';
    final base = build(normalized);
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

    final classicQueries = <String>{normalized};
    for (final formula in FormulaRepository.getAll()) {
      if (normalized.contains(formula.name)) classicQueries.add(formula.name);
    }
    for (final herb in HerbRepository.getAll()) {
      if (normalized.contains(herb.name)) classicQueries.add(herb.name);
    }
    for (final point in AcupointRepository.getAll()) {
      if (normalized.contains(point.name)) classicQueries.add(point.name);
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
      if (normalized.contains(phrase)) classicQueries.add(phrase);
    }
    for (final match in RegExp(r'(?:第|条文)\\s*(\\d+)\\s*条?').allMatches(normalized)) {
      final number = match.group(1);
      if (number != null) {
        classicQueries
          ..add('第${number}条')
          ..add('条文$number');
      }
    }

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
      final articleNumber = RegExp(r'(?:条文|第)\\s*(\\d+)').firstMatch(hit.title)?.group(1);
      buffer
        ..writeln('[App经典全文索引 · ${hit.sourceLabel} · ${hit.title}]')
        ..writeln('资料类型：${isLecture ? '倪师讲稿/整理讲义' : '古籍原文文本资产'}')
        ..writeln('本地来源：${hit.asset ?? 'assets/guji/${hit.bookId ?? 'unknown'}.txt'}')
        ..writeln('内部章节序号：${hit.chapterIndex?.toString() ?? 'MISSING'}')
        ..writeln('条文号：${articleNumber ?? 'MISSING'}（仅从标题显式提取，不由内部文件序号推断）')
        ..writeln('版本/底本/卷页：MISSING（需对照纸本影印本核验）')
        ..writeln('检索摘要：${hit.snippet}')
        ..writeln(
          isLecture
              ? '使用限制：这是讲稿或整理讲义，不得当作仲景原文、版本校勘或独立医案证据。'
              : '使用限制：这是本地古籍文本资产；在版本、卷页和异文核验完成前，不得声称已完成校勘。',
        );
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

    try {
      final cases = await getAllMedicalCases();
      final hits = cases
          .where((medicalCase) => terms.any(medicalCase.matches))
          .take(2)
          .toList(growable: false);
      for (final medicalCase in hits) {
        buffer
          ..writeln('[App医案库 assets/medical_cases/cases_table.md · 内部序号 ${medicalCase.seq}]')
          ..writeln('日期字段：${medicalCase.date.isEmpty ? 'MISSING' : medicalCase.date}')
          ..writeln('诊断字段：${medicalCase.diagnosis.isEmpty ? 'MISSING' : medicalCase.diagnosis}')
          ..writeln('病机字段：${medicalCase.mechanism.isEmpty ? 'MISSING' : medicalCase.mechanism}')
          ..writeln('方剂字段：${medicalCase.formula.isEmpty ? 'MISSING' : medicalCase.formula}')
          ..writeln('针灸字段：${medicalCase.acupuncture.isEmpty ? 'MISSING' : medicalCase.acupuncture}')
          ..writeln('治法字段：${medicalCase.method.isEmpty ? 'MISSING' : medicalCase.method}')
          ..writeln('结果字段：${medicalCase.result.isEmpty ? 'MISSING' : medicalCase.result}')
          ..writeln('来源定位：MISSING（内部序号不是原始病例页码或稳定来源 ID）')
          ..writeln('使用限制：仅作为本地整理记录检索，不代表已核验病例原文或疗效证据。');
      }
    } catch (_) {
      buffer.writeln('[App医案库] 读取失败，状态 MISSING。');
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
    });
    final keywordFormulaMatches = allFormulas.where((formula) =>
        formula.keywords.any((keyword) => normalized.contains(keyword)));
    final componentFormulaMatches = allFormulas.where((formula) =>
        formula.components.any(
          (component) => normalized.contains(component.name),
        ));
    final formulas = <Formula>[];
    for (final formula in [
      ...exactFormulaMatches,
      ...keywordFormulaMatches,
      ...componentFormulaMatches,
    ]) {
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

    final acupuncture = <AcupointEntry>[];
    for (final entry in AcupunctureRepository.getEntries()) {
      final matches = normalized.contains(entry.symptom) ||
          entry.aliases.any(normalized.contains) ||
          terms.any((term) =>
              entry.symptom.contains(term) ||
              entry.aliases.any((alias) => alias.contains(term)));
      if (matches && !acupuncture.any((item) => item.id == entry.id)) {
        acupuncture.add(entry);
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

    for (final entry in acupuncture) {
      buffer
        ..writeln('[App针灸处方库 assets/data/acupuncture.json · entry:${entry.id}]')
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
