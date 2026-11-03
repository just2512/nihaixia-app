import '../data/acupuncture_repository.dart';
import '../data/acupoint_repository.dart';
import '../data/formula_repository.dart';
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

  static String build(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return '';

    final terms = normalized
        .split(RegExp(r'[，。！？、；：,.!?;\\s]+'))
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
