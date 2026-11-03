import '../data/formula_repository.dart';
import '../data/herb_repository.dart';

/// Bounded keyword retrieval from the app's bundled TCM knowledge data.
/// Returns source-labelled excerpts, never a diagnosis or prescription.
class AssistantKnowledgeContextBuilder {
  static const int maxContextCharacters = 6500;
  static const int maxFormulaEntries = 4;
  static const int maxHerbEntries = 5;

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
    final formulas = <dynamic>[];
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

    if (formulas.isEmpty && herbs.isEmpty) return '';

    final buffer = StringBuffer()
      ..writeln('以下内容来自 App 内置数据，仅作为可核对的参考资料。')
      ..writeln('不得把条目描述改写成对用户的诊断、处方或剂量建议。');

    for (final formula in formulas) {
      buffer
        ..writeln('[App方剂库 assets/data/formulas.json · ' + formula.id + ']')
        ..writeln('方名：' + formula.name)
        ..writeln('别名：' + formula.alias)
        ..writeln('归经/分类：' + formula.meridian + ' / ' + formula.category)
        ..writeln('原始适应证字段：' + formula.indication)
        ..writeln('原始解释字段：' + formula.explanation)
        ..writeln('组成药名：' + formula.components.map((item) => item.name).join('、'));
      if (formula.contraindication.trim().isNotEmpty) {
        buffer.writeln('原始禁忌字段：' + formula.contraindication);
      }
    }

    for (final herb in herbs) {
      buffer
        ..writeln('[App本草库 assets/data/herbs.json · ' + herb.name + ']')
        ..writeln('药名：' + herb.name)
        ..writeln('性味：' + (herb.nature ?? 'MISSING') + '；' + herb.flavor)
        ..writeln('归经字段：' + herb.meridians.join('、'))
        ..writeln('功用字段：' + (herb.action ?? 'MISSING'));
      if ((herb.contraindication ?? '').trim().isNotEmpty) {
        buffer.writeln('原始禁忌字段：' + herb.contraindication!);
      }
      if ((herb.historicalNotes ?? '').trim().isNotEmpty) {
        buffer.writeln('历史备注字段：' + herb.historicalNotes!);
      }
    }

    final result = buffer.toString().trim();
    if (result.length <= maxContextCharacters) return result;
    return result.substring(0, maxContextCharacters);
  }
}
