import '../models/assistant_tool_result.dart';
import 'solar_term_service.dart';

/// Headless query adapter for the existing solar-term service and knowledge asset.
///
/// It does not derive solar terms or rewrite health content. It only reads
/// getCurrentSolarTerm / getSolarTermKnowledge and returns their source fields
/// for constrained assistant explanation.
class SolarTermToolExecutor {
  static const String sourceId = 'local-engine:solar-term-service';
  static const String knowledgeSourceId = 'local-asset:solar-term-knowledge';

  static const List<String> termNames = [
    '立春',
    '雨水',
    '惊蛰',
    '春分',
    '清明',
    '谷雨',
    '立夏',
    '小满',
    '芒种',
    '夏至',
    '小暑',
    '大暑',
    '立秋',
    '处暑',
    '白露',
    '秋分',
    '寒露',
    '霜降',
    '立冬',
    '小雪',
    '大雪',
    '冬至',
    '小寒',
    '大寒',
  ];

  static const Set<String> _allowedArguments = {'term'};

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !_allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的节气查询参数，本次未执行。');
    }

    final requestedTerm = arguments['term']?.trim();
    if (requestedTerm != null && !termNames.contains(requestedTerm)) {
      return _failure(arguments, '无法识别节气「$requestedTerm」；请从二十四节气名称中明确选择。');
    }

    try {
      final isCurrentQuery = requestedTerm == null || requestedTerm.isEmpty;
      final current = isCurrentQuery ? getCurrentSolarTerm() : null;
      final term = isCurrentQuery ? current?.currentTerm ?? '' : requestedTerm!;
      if (term.isEmpty || (isCurrentQuery && current.nextTerm.isEmpty)) {
        return _failure(arguments, 'App 节气服务当前未返回有效节气信息，本次未生成解释结果。');
      }

      final knowledge = await getSolarTermKnowledge(term);
      if (knowledge == null || knowledge.term != term) {
        return _failure(arguments, '本地节气知识资产中没有「$term」的可用记录，本次不生成推断内容。');
      }

      final values = <String, String>{
        '查询类型': isCurrentQuery ? '当前节气' : '指定节气知识',
        '目标节气': term,
        '公历约期': getTermApproxDate(term).isEmpty
            ? 'MISSING'
            : getTermApproxDate(term),
        '太阳黄经': '${getTermSolarLongitude(term)}°',
        '通用养生常识': knowledge.health.isEmpty ? 'MISSING' : knowledge.health,
        '倪师讲座相关整理': knowledge.niShi.isEmpty ? 'MISSING' : knowledge.niShi,
        '节气三候': knowledge.phenology.isEmpty
            ? 'MISSING'
            : knowledge.phenology.join('；'),
        '起居调摄': knowledge.dailyRegimen.isEmpty
            ? 'MISSING'
            : knowledge.dailyRegimen,
        '食疗资料': knowledge.dietRecipe.isEmpty
            ? 'MISSING'
            : knowledge.dietRecipe,
        if (current != null) ...{
          '当前节气': current.currentTerm,
          '下一节气': current.nextTerm,
          '进入当前节气天数': current.daysInto.toString(),
          '距下一节气天数': current.daysLeft.toString(),
          '当前节气养生提示': current.healthTip,
          '节气计算口径': 'App solar_term_service / sxwnl_spa_dart，节气内部按 UTC+8 北京时间计算',
        },
      };

      return AssistantToolResult(
        toolId: 'solar_terms',
        title: '节气养生',
        values: Map<String, String>.unmodifiable(values),
        sourceIds: const [sourceId, knowledgeSourceId],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '节气日期和节点由 App 现有节气服务计算，养生内容来自 App 现有 solar_term_knowledge.json。内容仅作传统节气文化与一般养生知识参考，不构成个体诊断、治疗或用药建议；AI 只负责解释来源内容，不补造节气数据或个体医学结论。',
      );
    } catch (error) {
      return _failure(arguments, 'App 节气服务执行失败：$error');
    }
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'solar_terms',
        title: '节气养生',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '节气查询失败或来源资料缺失；本次未生成事实性解释。',
      );
}
