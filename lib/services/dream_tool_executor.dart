import '../data/dream_data.dart';
import '../models/assistant_tool_result.dart';

/// Headless lookup adapter for the app's existing 412-entry folk-dream dataset.
///
/// It returns source records only. It does not create an interpretation, rank
/// candidates, or predict real-world events.
class DreamToolExecutor {
  static const String sourceId = 'local-data:dream-dataset-412';
  static const Set<String> _allowedArguments = {'dream_text'};

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的解梦参数；本次未执行检索。');
    }

    final rawDescription = arguments['dream_text']?.trim() ?? '';
    if (rawDescription.isEmpty) {
      return _failure(arguments, '缺少梦境描述；请先说明梦中出现的事物和具体情节。');
    }

    final matches = _matchingEntries(rawDescription);
    final normalizedArguments = Map<String, String>.unmodifiable({
      'dream_text': rawDescription,
    });
    if (matches.isEmpty) {
      return AssistantToolResult(
        toolId: 'dream',
        title: '周公解梦',
        status: AssistantToolExecutionStatus.noResult,
        values: {
          '检索状态': 'NO_MATCH',
          '用户梦境描述': rawDescription,
          '未匹配说明':
              '本地民俗资料中没有找到可直接匹配的情节或关键词。请补充梦中具体出现的事物、动作、场景或变化；本次没有生成解释结论。',
        },
        sourceIds: const [sourceId],
        arguments: normalizedArguments,
        disclaimer: _disclaimer,
      );
    }

    final isSingleMatch = matches.length == 1;
    final values = <String, String>{
      '检索状态':
          isSingleMatch ? 'SINGLE_MATCH' : 'CANDIDATES_REQUIRE_CLARIFICATION',
      '检索依据': _hasScenarioMatch(rawDescription)
          ? '梦境具体情节与本地梦境词条匹配'
          : '梦境描述中的关键词与本地资料匹配',
      '用户梦境描述': rawDescription,
      '候选总数': matches.length.toString(),
    };

    if (isSingleMatch) {
      final entry = matches.single;
      values.addAll({
        '词条ID': entry.id,
        '分类': entry.category + ' / ' + entry.subcategory,
        '匹配关键词': entry.keyword,
        '梦境词条': entry.dream,
        '词条释义原文': entry.interpretation,
        '原始吉凶标签（民俗文本）': entry.auspicious,
        '词条来源字段': entry.source,
      });
    } else {
      const maxCandidates = 8;
      final visibleCandidates = matches.take(maxCandidates).toList();
      values['候选列表（按数据集原始顺序，不代表相关度）'] =
          visibleCandidates.map(_formatCandidate).join('\n\n');
      if (matches.length > visibleCandidates.length) {
        values['未展开候选数'] =
            (matches.length - visibleCandidates.length).toString();
      }
      values['澄清要求'] =
          '多个词条均可能相关，尚未确定用户梦境对应哪一条；不得替用户选择。需要用户补充或确认具体情节。';
    }

    return AssistantToolResult(
      toolId: 'dream',
      title: '周公解梦',
      values: Map<String, String>.unmodifiable(values),
      sourceIds: const [sourceId],
      arguments: normalizedArguments,
      disclaimer: _disclaimer,
    );
  }

  static bool _hasScenarioMatch(String rawDescription) {
    final description = _normalizeDescription(rawDescription);
    return kDreamEntries.any((entry) {
      final scenario = _normalizeDescription(entry.dream);
      return scenario.length >= 2 && description.contains(scenario);
    });
  }

  static List<DreamEntry> _matchingEntries(String rawDescription) {
    final description = _normalizeDescription(rawDescription);
    if (description.isEmpty) return const [];

    // Prefer concrete scenario phrases. One-character scenarios such as “蛇”
    // are intentionally excluded so repeated keywords cannot select item one.
    final exactScenarios = kDreamEntries.where((entry) {
      final scenario = _normalizeDescription(entry.dream);
      return scenario.length >= 2 && description.contains(scenario);
    }).toList(growable: false);
    if (exactScenarios.isNotEmpty) return exactScenarios;

    final matchedKeywords = kDreamEntries
        .map((entry) => entry.keyword.trim())
        .where((keyword) =>
            keyword.isNotEmpty &&
            description.contains(_normalizeDescription(keyword)))
        .toSet();

    final specificKeywords = matchedKeywords.where((keyword) {
      final normalizedKeyword = _normalizeDescription(keyword);
      return !matchedKeywords.any((other) {
        if (other == keyword) return false;
        final normalizedOther = _normalizeDescription(other);
        return normalizedOther.length > normalizedKeyword.length &&
            normalizedOther.contains(normalizedKeyword);
      });
    }).toSet();

    return kDreamEntries
        .where((entry) => specificKeywords.contains(entry.keyword))
        .toList(growable: false);
  }

  static String _normalizeDescription(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'(?:补充梦境细节|昨天晚上|昨晚|昨天|前天|今晚|今早|今天|最近|做了一个梦|做了个梦|做梦时|做梦|梦见|梦到|梦里有|梦里|梦境(?:是|里)?|帮我|麻烦|请|解梦|解读|解释|分析|一下|什么意思|是什么意思|怎么理解|代表什么|这个梦|一条|一只|一群|一个|很多|看到|看见|出现|被|我|有|是|了|的)',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，,。.!！?？；;：:、()（）【】\[\]“”"‘’·]+'), '');
  }

  static String _formatCandidate(DreamEntry entry) => [
        '词条ID：' + entry.id,
        '分类：' + entry.category + ' / ' + entry.subcategory,
        '匹配关键词：' + entry.keyword,
        '梦境词条：' + entry.dream,
        '词条释义原文：' + entry.interpretation,
        '原始吉凶标签（民俗文本）：' + entry.auspicious,
        '词条来源字段：' + entry.source,
      ].join('\n');

  static const String _disclaimer =
      '内容来自 App 本地梦境民俗文本数据集。' +
      kDreamDisclaimer +
      ' 吉凶标签和释义仅代表数据集中的传统文本，不是事实判断或现实预测。AI 只归纳已返回的词条，不新增断言。';

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) {
    return AssistantToolResult(
      toolId: 'dream',
      title: '周公解梦',
      status: AssistantToolExecutionStatus.failed,
      values: {'未执行原因': reason},
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '输入校验未通过；本次未产生梦境检索结果。',
    );
  }
}
