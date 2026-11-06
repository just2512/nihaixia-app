import 'package:flutter/material.dart';

import 'chenggu_bone_screen.dart';
import 'critical_illness_list_screen.dart';
import 'daily_almanac_screen.dart';
import 'diagnosis_history_screen.dart';
import 'dosage_converter_screen.dart';
import 'dream_screen.dart';
import 'guansha_screen.dart';
import 'guji_library_screen.dart';
import 'huangdi_siji_screen.dart';
import 'medical_case_library_screen.dart';
import 'meihua_screen.dart';
import 'sanshan_lingqian_screen.dart';
import 'saved_charts_screen.dart';
import 'shousheng_debt_screen.dart';
import 'solar_term_section_screen.dart';
import 'ziwei_chart_screen.dart';
import 'bazi_paipan_screen.dart';
import 'xiaoliuren_screen.dart';
import 'yijing_screen.dart';
import 'yunqi_screen.dart';
import 'yuxiaji_omen_screen.dart';
import 'ziwuliuzhu_screen.dart';

enum AssistantMode { automatic, consultation, learning, tools, metaphysics }

extension AssistantModePresentation on AssistantMode {
  String get label => switch (this) {
        AssistantMode.automatic => '自动调度',
        AssistantMode.consultation => '问诊助手',
        AssistantMode.learning => '学习助手',
        AssistantMode.tools => '工具助手',
        AssistantMode.metaphysics => '玄学大师',
      };

  String get promptHint => switch (this) {
        AssistantMode.automatic => '先识别任务领域；明确工具动作交给 App 工具，个人症状进入问诊，知识问题进入学习。意图不清时先澄清，不猜测。',
        AssistantMode.consultation => '围绕用户自述澄清症状，不替代规则辨证，不自动诊断或开方。',
        AssistantMode.learning => '围绕中医知识学习；优先引用 App 检索到的本地条目，缺少来源时明确标记 MISSING。',
        AssistantMode.tools => '只说明 App 已实现的工具能力；实际计算必须打开对应工具执行，不得猜算结果。',
        AssistantMode.metaphysics => '你是玄学大师，只能提供传统术数与民俗文化参考；明确说明非科学预测，不用于医疗、法律或投资决策。排盘与推算必须调用 App 内置工具，不得凭空生成结果。',
      };
}

class AssistantToolParameter {
  const AssistantToolParameter({
    required this.key,
    required this.label,
    required this.type,
    this.isRequired = false,
    this.description,
    this.choices = const [],
  });

  final String key;
  final String label;
  final AssistantToolParameterType type;
  final bool isRequired;
  final String? description;
  final List<String> choices;
}

enum AssistantToolParameterType { text, date, integer, choice }

class AssistantToolArguments {
  const AssistantToolArguments({
    required this.toolId,
    this.values = const {},
  });

  final String toolId;
  final Map<String, String> values;

  String? operator [](String key) => values[key];

  /// Validate a tool call at the execution boundary. Intent matching alone is
  /// not permission to pass malformed or undeclared arguments to a screen.
  List<String> validateAgainst(AssistantToolDefinition tool) {
    final errors = <String>[];
    if (toolId != tool.id) {
      errors.add('工具标识不匹配：' + toolId + ' != ' + tool.id);
      return List.unmodifiable(errors);
    }
    final declared = {for (final parameter in tool.parameters) parameter.key};
    for (final key in values.keys) {
      if (!declared.contains(key)) errors.add('未声明的参数：' + key);
    }
    for (final parameter in tool.parameters) {
      final raw = values[parameter.key]?.trim();
      if (raw == null || raw.isEmpty) {
        if (parameter.isRequired) {
          errors.add('缺少必填参数：' + parameter.label);
        }
        continue;
      }
      switch (parameter.type) {
        case AssistantToolParameterType.date:
          final parsed = DateTime.tryParse(raw);
          final normalized = parsed == null
              ? ''
              : parsed.year.toString().padLeft(4, '0') + '-' +
                  parsed.month.toString().padLeft(2, '0') + '-' +
                  parsed.day.toString().padLeft(2, '0');
          if (normalized != raw) {
            errors.add('参数「' + parameter.label + '」必须是有效日期 YYYY-MM-DD');
          }
          break;
        case AssistantToolParameterType.integer:
          if (int.tryParse(raw) == null) {
            errors.add('参数「' + parameter.label + '」必须是整数');
          }
          break;
        case AssistantToolParameterType.choice:
          if (!parameter.choices.contains(raw)) {
            errors.add('参数「' + parameter.label + '」不在允许选项内');
          }
          break;
        case AssistantToolParameterType.text:
          break;
      }
    }
    return List.unmodifiable(errors);
  }
}

class AssistantToolDefinition {
  final String id;
  final String title;
  final String description;
  final Set<AssistantMode> modes;
  final List<String> aliases;
  final List<String> actionWords;
  final Widget Function() builder;
  final Widget Function(AssistantToolArguments arguments)? builderWithArguments;
  final List<AssistantToolParameter> parameters;

  const AssistantToolDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.modes,
    required this.aliases,
    required this.actionWords,
    required this.builder,
    this.builderWithArguments,
    this.parameters = const [],
  });
}

/// Deterministic intent-to-screen registry. The model never fabricates tool
/// output: a matched request opens the existing in-app calculator/page.
class AssistantToolRouter {
  static const structuredDiagnosis = AssistantToolDefinition(
    id: 'structured_diagnosis',
    title: '结构化辨证问诊',
    description: '按现有六经规则逐项问诊；完成后把记录带回助手对话。',
    modes: {AssistantMode.consultation},
    aliases: ['结构化辨证', '规则辨证', '结构化问诊', '规则问诊', '六经问诊'],
    actionWords: ['开始', '进入', '进行', '帮我', '我要', '打开'],
    builder: _buildStructuredDiagnosis,
  );

  static const yunqi = AssistantToolDefinition(
    id: 'yunqi',
    title: '五运六气推算',
    description: '打开本地五运六气计算器。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['五运六气', '运气推算', '岁运司天在泉'],
    actionWords: ['推算', '计算', '算一下', '起算', '帮我算'],
    parameters: [
      AssistantToolParameter(
        key: 'date',
        label: '推算日期',
        type: AssistantToolParameterType.date,
        description: 'YYYY-MM-DD；未提供时使用当前日期。',
      ),
    ],
    builder: _buildYunqi,
    builderWithArguments: _buildYunqiWithArguments,
  );

  static const ziwei = AssistantToolDefinition(
    id: 'ziwei',
    title: '紫微斗数排盘',
    description: '打开本地紫微斗数排盘。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['紫微斗数', '紫微排盘', '紫微命盘'],
    actionWords: ['排盘', '起盘', '命盘', '帮我排'],
    builder: _buildZiwei,
  );

  static const bazi = AssistantToolDefinition(
    id: 'bazi',
    title: '八字排盘',
    description: '打开本地四柱八字排盘。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['八字', '四柱', '生辰八字'],
    actionWords: ['排盘', '起盘', '命盘', '帮我排'],
    builder: _buildBazi,
  );

  static const yijing = AssistantToolDefinition(
    id: 'yijing',
    title: '易经起卦',
    description: '打开本地易经六十四卦工具。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['易经', '六十四卦', '周易'],
    actionWords: ['起卦', '占卦', '卜卦', '排卦'],
    builder: _buildYijing,
  );

  static const xiaoliuren = AssistantToolDefinition(
    id: 'xiaoliuren',
    title: '小六壬起课',
    description: '打开本地小六壬工具。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['小六壬'],
    actionWords: ['起课', '起卦', '推算', '算一下'],
    builder: _buildXiaoliuren,
  );

  static const meihua = AssistantToolDefinition(
    id: 'meihua',
    title: '梅花易数起卦',
    description: '打开本地梅花易数工具。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['梅花易数', '梅花'],
    actionWords: ['起卦', '推算', '算一下'],
    builder: _buildMeihua,
  );

  static const dosage = AssistantToolDefinition(
    id: 'dosage',
    title: '经方剂量换算',
    description: '打开古代度量衡换算器。',
    modes: {AssistantMode.tools},
    aliases: ['剂量换算', '经方换算', '两升铢', '古代度量衡'],
    actionWords: ['换算', '计算', '转换'],
    builder: _buildDosage,
  );

  static const ziwu = AssistantToolDefinition(
    id: 'ziwu_liuzhu',
    title: '时辰开穴计算',
    description: '打开中医时辰开穴综合计算器。',
    modes: {AssistantMode.tools},
    aliases: ['时辰开穴', '子午流注', '灵龟八法', '纳子法', '纳甲法'],
    actionWords: ['计算', '开穴', '推算', '查穴'],
    builder: _buildZiwu,
  );

  static const guji = AssistantToolDefinition(
    id: 'guji_library',
    title: '古籍原文',
    description: '打开 App 内置古籍阅读库。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['古籍', '经典原文', '灵枢', '针灸大成'],
    actionWords: ['查原文', '查阅', '打开', '阅读'],
    builder: _buildGuji,
  );

  static const medicalCases = AssistantToolDefinition(
    id: 'medical_cases',
    title: '医案库检索',
    description: '打开本地医案库进行检索。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['医案库', '医案', '病例库'],
    actionWords: ['检索', '查找', '查案例', '打开'],
    builder: _buildMedicalCases,
  );

  static const almanac = AssistantToolDefinition(
    id: 'almanac',
    title: '每日黄历',
    description: '打开本地黄历查询。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['黄历', '每日宜忌', '今日宜忌'],
    actionWords: ['查询', '查看', '打开', '今天'],
    builder: _buildAlmanac,
  );

  // Existing ToolsScreen destinations must be addressable from the unified
  // assistant as well. These screens remain the deterministic execution
  // surface; the model only routes and explains, never fabricates results.
  static const diagnosisHistory = AssistantToolDefinition(
    id: 'diagnosis_history',
    title: '诊断历史趋势',
    description: '查看既有结构化辨证记录与六经变化趋势。',
    modes: {AssistantMode.tools, AssistantMode.consultation},
    aliases: ['诊断历史', '问诊历史', '辨证历史', '历史趋势'],
    actionWords: ['查看', '打开', '回看', '趋势'],
    builder: _buildDiagnosisHistory,
  );

  static const criticalIllness = AssistantToolDefinition(
    id: 'critical_illness',
    title: '闭门课重症资料',
    description: '查阅 App 内置重症课程资料；不是个体治疗方案。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['闭门课', '重症临床', '重症资料', '重症课程'],
    actionWords: ['查阅', '查看', '学习', '打开', '介绍'],
    builder: _buildCriticalIllness,
  );

  static const solarTerms = AssistantToolDefinition(
    id: 'solar_terms',
    title: '节气养生',
    description: '查看二十四节气知识、起居与食养资料。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['节气养生', '二十四节气', '节气知识'],
    actionWords: ['查看', '学习', '查阅', '打开', '介绍'],
    builder: _buildSolarTerms,
  );

  static const yuxiaji = AssistantToolDefinition(
    id: 'yuxiaji_omen',
    title: '玉匣灵兆',
    description: '打开传统民俗身体兆占查询；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['玉匣灵兆', '玉匣记', '面热占', '眼跳占', '耳鸣占', '心惊占'],
    actionWords: ['查询', '查看', '起占', '打开', '推算'],
    builder: _buildYuxiaji,
  );

  static const dream = AssistantToolDefinition(
    id: 'dream',
    title: '周公解梦',
    description: '检索传统梦境释义；不作现实吉凶判断。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['周公解梦', '解梦', '梦境释义'],
    actionWords: ['查询', '查看', '解释', '检索', '搜索', '打开'],
    builder: _buildDream,
  );

  static const guansha = AssistantToolDefinition(
    id: 'guansha',
    title: '小儿关煞',
    description: '打开传统民俗关煞资料和排算页面；非医学结论。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['小儿关煞', '关煞', '小孩关煞'],
    actionWords: ['查询', '查看', '测算', '排算', '打开'],
    builder: _buildGuansha,
  );

  static const sanshan = AssistantToolDefinition(
    id: 'sanshan_lingqian',
    title: '三山国王灵签',
    description: '打开传统签谱与求签页面；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['三山国王', '三山灵签', '灵签'],
    actionWords: ['求签', '抽签', '抽', '查看', '查签', '打开'],
    builder: _buildSanshan,
  );

  static const chenggu = AssistantToolDefinition(
    id: 'chenggu',
    title: '袁天罡称骨',
    description: '打开传统称骨计算；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['称骨', '袁天罡', '称骨算命'],
    actionWords: ['计算', '测算', '查询', '打开'],
    builder: _buildChenggu,
  );

  static const shoushengDebt = AssistantToolDefinition(
    id: 'shousheng_debt',
    title: '受生债查询',
    description: '查阅传统道教文献与民俗计算；不构成宗教或财务建议。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['受生债', '禄库受生经', '五斗金章'],
    actionWords: ['查询', '计算', '测算', '打开'],
    builder: _buildShoushengDebt,
  );

  static const huangdiSiji = AssistantToolDefinition(
    id: 'huangdi_siji',
    title: '轩辕黄帝四季歌',
    description: '打开传统四季歌查询；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['黄帝四季歌', '轩辕黄帝四季歌', '四季歌'],
    actionWords: ['查询', '查看', '测算', '打开'],
    builder: _buildHuangdiSiji,
  );

  static const savedCharts = AssistantToolDefinition(
    id: 'saved_charts',
    title: '我的命盘库',
    description: '查看已保存的生辰资料与命盘。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['我的命盘库', '保存的命盘', '已保存命盘'],
    actionWords: ['查看', '打开', '管理', '回看'],
    builder: _buildSavedCharts,
  );

  static const List<AssistantToolDefinition> _all = [
    structuredDiagnosis,
    yunqi,
    ziwei,
    bazi,
    yijing,
    xiaoliuren,
    meihua,
    dosage,
    ziwu,
    guji,
    medicalCases,
    almanac,
    diagnosisHistory,
    criticalIllness,
    solarTerms,
    yuxiaji,
    dream,
    guansha,
    sanshan,
    chenggu,
    shoushengDebt,
    huangdiSiji,
    savedCharts,
  ];

  static List<AssistantToolDefinition> get all =>
      List.unmodifiable(_all);

  static List<AssistantToolDefinition> quickActions(AssistantMode mode) =>
      _all.where((tool) => mode == AssistantMode.automatic || tool.modes.contains(mode)).toList(growable: false);

  /// Resolve a persisted tool action when a conversation is reopened.
  static AssistantToolDefinition? byId(String id) {
    for (final tool in _all) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  /// Match a short answer to a prior tool-type clarification. Unlike [match],
  /// this does not require an action verb; callers must require exactly one match.
  static List<AssistantToolDefinition> matchAliases(
    String query,
    AssistantMode mode,
  ) {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _all.where((tool) =>
      tool.modes.contains(mode) && tool.aliases.any(normalized.contains)
    ).toList(growable: false);
  }

  /// Return every explicit action match. Callers must clarify when more than
  /// one tool is named; silently selecting the first registry entry is unsafe.
  static List<AssistantToolDefinition> matchAll(
    String query,
    AssistantMode mode,
  ) {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _all.where((tool) {
      if (mode != AssistantMode.automatic && !tool.modes.contains(mode)) {
        return false;
      }
      return tool.aliases.any(normalized.contains) &&
          tool.actionWords.any(normalized.contains);
    }).toList(growable: false);
  }

  static AssistantToolDefinition? match(String query, AssistantMode mode) {
    final matches = matchAll(query, mode);
    return matches.length == 1 ? matches.single : null;
  }

  static Widget _buildStructuredDiagnosis() =>
      throw StateError(
        'Structured diagnosis must run inside LocalAiInterviewScreen; '
        'the legacy ChatScreen entry is disabled.',
      );
  static Widget _buildYunqi() => const YunQiScreen(returnResultOnComplete: true);
  static Widget _buildYunqiWithArguments(AssistantToolArguments arguments) {
    final rawDate = arguments['date'];
    final date = rawDate == null ? null : DateTime.tryParse(rawDate);
    return YunQiScreen(
      returnResultOnComplete: true,
      initialDate: date,
    );
  }
  static Widget _buildZiwei() =>
      const ZiweiChartScreen(returnResultOnComplete: true);
  static Widget _buildBazi() =>
      const BaZiPaipanScreen(returnResultOnComplete: true);
  static Widget _buildYijing() =>
      const YiJingScreen(returnResultOnComplete: true);
  static Widget _buildXiaoliuren() =>
      const XiaoliurenScreen(returnResultOnComplete: true);
  static Widget _buildMeihua() =>
      const MeihuaScreen(returnResultOnComplete: true);
  static Widget _buildDosage() =>
      const DosageConverterScreen(returnResultOnComplete: true);
  static Widget _buildZiwu() => const ZiWuLiuZhuScreen(returnResultOnComplete: true);
  static Widget _buildGuji() => const GujiLibraryScreen();
  static Widget _buildMedicalCases() => const MedicalCaseLibraryScreen();
  static Widget _buildAlmanac() =>
      const DailyAlmanacScreen(returnResultOnComplete: true);
  static Widget _buildDiagnosisHistory() => const DiagnosisHistoryScreen();
  static Widget _buildCriticalIllness() => const CriticalIllnessListScreen();
  static Widget _buildSolarTerms() => const SolarTermSectionScreen();
  static Widget _buildYuxiaji() => const YuxiajiOmenScreen();
  static Widget _buildDream() => const DreamScreen();
  static Widget _buildGuansha() => const GuanshaScreen();
  static Widget _buildSanshan() => const SanshanLingqianScreen();
  static Widget _buildChenggu() => const ChengguBoneScreen();
  static Widget _buildShoushengDebt() => const ShoushengDebtScreen();
  static Widget _buildHuangdiSiji() => const HuangdiSijiScreen();
  static Widget _buildSavedCharts() => const SavedChartsScreen();
}
).hasMatch(raw) ||
              '${parsed.year.toString().padLeft(4, '0')}-'
                  '${parsed.month.toString().padLeft(2, '0')}-'
                  '${parsed.day.toString().padLeft(2, '0')}' != raw) {
            errors.add('参数「${parameter.label}」必须是有效日期 YYYY-MM-DD');
          }
        case AssistantToolParameterType.integer:
          if (int.tryParse(raw) == null) {
            errors.add('参数「${parameter.label}」必须是整数');
          }
        case AssistantToolParameterType.choice:
          if (!parameter.choices.contains(raw)) {
            errors.add('参数「${parameter.label}」不在允许选项内');
          }
        case AssistantToolParameterType.text:
          break;
      }
    }
    return List.unmodifiable(errors);
  }
}

class AssistantToolDefinition {
  final String id;
  final String title;
  final String description;
  final Set<AssistantMode> modes;
  final List<String> aliases;
  final List<String> actionWords;
  final Widget Function() builder;
  final Widget Function(AssistantToolArguments arguments)? builderWithArguments;
  final List<AssistantToolParameter> parameters;

  const AssistantToolDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.modes,
    required this.aliases,
    required this.actionWords,
    required this.builder,
    this.builderWithArguments,
    this.parameters = const [],
  });
}

/// Deterministic intent-to-screen registry. The model never fabricates tool
/// output: a matched request opens the existing in-app calculator/page.
class AssistantToolRouter {
  static const structuredDiagnosis = AssistantToolDefinition(
    id: 'structured_diagnosis',
    title: '结构化辨证问诊',
    description: '按现有六经规则逐项问诊；完成后把记录带回助手对话。',
    modes: {AssistantMode.consultation},
    aliases: ['结构化辨证', '规则辨证', '结构化问诊', '规则问诊', '六经问诊'],
    actionWords: ['开始', '进入', '进行', '帮我', '我要', '打开'],
    builder: _buildStructuredDiagnosis,
  );

  static const yunqi = AssistantToolDefinition(
    id: 'yunqi',
    title: '五运六气推算',
    description: '打开本地五运六气计算器。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['五运六气', '运气推算', '岁运司天在泉'],
    actionWords: ['推算', '计算', '算一下', '起算', '帮我算'],
    parameters: [
      AssistantToolParameter(
        key: 'date',
        label: '推算日期',
        type: AssistantToolParameterType.date,
        description: 'YYYY-MM-DD；未提供时使用当前日期。',
      ),
    ],
    builder: _buildYunqi,
    builderWithArguments: _buildYunqiWithArguments,
  );

  static const ziwei = AssistantToolDefinition(
    id: 'ziwei',
    title: '紫微斗数排盘',
    description: '打开本地紫微斗数排盘。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['紫微斗数', '紫微排盘', '紫微命盘'],
    actionWords: ['排盘', '起盘', '命盘', '帮我排'],
    builder: _buildZiwei,
  );

  static const bazi = AssistantToolDefinition(
    id: 'bazi',
    title: '八字排盘',
    description: '打开本地四柱八字排盘。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['八字', '四柱', '生辰八字'],
    actionWords: ['排盘', '起盘', '命盘', '帮我排'],
    builder: _buildBazi,
  );

  static const yijing = AssistantToolDefinition(
    id: 'yijing',
    title: '易经起卦',
    description: '打开本地易经六十四卦工具。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['易经', '六十四卦', '周易'],
    actionWords: ['起卦', '占卦', '卜卦', '排卦'],
    builder: _buildYijing,
  );

  static const xiaoliuren = AssistantToolDefinition(
    id: 'xiaoliuren',
    title: '小六壬起课',
    description: '打开本地小六壬工具。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['小六壬'],
    actionWords: ['起课', '起卦', '推算', '算一下'],
    builder: _buildXiaoliuren,
  );

  static const meihua = AssistantToolDefinition(
    id: 'meihua',
    title: '梅花易数起卦',
    description: '打开本地梅花易数工具。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['梅花易数', '梅花'],
    actionWords: ['起卦', '推算', '算一下'],
    builder: _buildMeihua,
  );

  static const dosage = AssistantToolDefinition(
    id: 'dosage',
    title: '经方剂量换算',
    description: '打开古代度量衡换算器。',
    modes: {AssistantMode.tools},
    aliases: ['剂量换算', '经方换算', '两升铢', '古代度量衡'],
    actionWords: ['换算', '计算', '转换'],
    builder: _buildDosage,
  );

  static const ziwu = AssistantToolDefinition(
    id: 'ziwu_liuzhu',
    title: '时辰开穴计算',
    description: '打开中医时辰开穴综合计算器。',
    modes: {AssistantMode.tools},
    aliases: ['时辰开穴', '子午流注', '灵龟八法', '纳子法', '纳甲法'],
    actionWords: ['计算', '开穴', '推算', '查穴'],
    builder: _buildZiwu,
  );

  static const guji = AssistantToolDefinition(
    id: 'guji_library',
    title: '古籍原文',
    description: '打开 App 内置古籍阅读库。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['古籍', '经典原文', '灵枢', '针灸大成'],
    actionWords: ['查原文', '查阅', '打开', '阅读'],
    builder: _buildGuji,
  );

  static const medicalCases = AssistantToolDefinition(
    id: 'medical_cases',
    title: '医案库检索',
    description: '打开本地医案库进行检索。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['医案库', '医案', '病例库'],
    actionWords: ['检索', '查找', '查案例', '打开'],
    builder: _buildMedicalCases,
  );

  static const almanac = AssistantToolDefinition(
    id: 'almanac',
    title: '每日黄历',
    description: '打开本地黄历查询。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['黄历', '每日宜忌', '今日宜忌'],
    actionWords: ['查询', '查看', '打开', '今天'],
    builder: _buildAlmanac,
  );

  // Existing ToolsScreen destinations must be addressable from the unified
  // assistant as well. These screens remain the deterministic execution
  // surface; the model only routes and explains, never fabricates results.
  static const diagnosisHistory = AssistantToolDefinition(
    id: 'diagnosis_history',
    title: '诊断历史趋势',
    description: '查看既有结构化辨证记录与六经变化趋势。',
    modes: {AssistantMode.tools, AssistantMode.consultation},
    aliases: ['诊断历史', '问诊历史', '辨证历史', '历史趋势'],
    actionWords: ['查看', '打开', '回看', '趋势'],
    builder: _buildDiagnosisHistory,
  );

  static const criticalIllness = AssistantToolDefinition(
    id: 'critical_illness',
    title: '闭门课重症资料',
    description: '查阅 App 内置重症课程资料；不是个体治疗方案。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['闭门课', '重症临床', '重症资料', '重症课程'],
    actionWords: ['查阅', '查看', '学习', '打开', '介绍'],
    builder: _buildCriticalIllness,
  );

  static const solarTerms = AssistantToolDefinition(
    id: 'solar_terms',
    title: '节气养生',
    description: '查看二十四节气知识、起居与食养资料。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: ['节气养生', '二十四节气', '节气知识'],
    actionWords: ['查看', '学习', '查阅', '打开', '介绍'],
    builder: _buildSolarTerms,
  );

  static const yuxiaji = AssistantToolDefinition(
    id: 'yuxiaji_omen',
    title: '玉匣灵兆',
    description: '打开传统民俗身体兆占查询；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['玉匣灵兆', '玉匣记', '面热占', '眼跳占', '耳鸣占', '心惊占'],
    actionWords: ['查询', '查看', '起占', '打开', '推算'],
    builder: _buildYuxiaji,
  );

  static const dream = AssistantToolDefinition(
    id: 'dream',
    title: '周公解梦',
    description: '检索传统梦境释义；不作现实吉凶判断。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['周公解梦', '解梦', '梦境释义'],
    actionWords: ['查询', '查看', '解释', '检索', '搜索', '打开'],
    builder: _buildDream,
  );

  static const guansha = AssistantToolDefinition(
    id: 'guansha',
    title: '小儿关煞',
    description: '打开传统民俗关煞资料和排算页面；非医学结论。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['小儿关煞', '关煞', '小孩关煞'],
    actionWords: ['查询', '查看', '测算', '排算', '打开'],
    builder: _buildGuansha,
  );

  static const sanshan = AssistantToolDefinition(
    id: 'sanshan_lingqian',
    title: '三山国王灵签',
    description: '打开传统签谱与求签页面；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['三山国王', '三山灵签', '灵签'],
    actionWords: ['求签', '抽签', '抽', '查看', '查签', '打开'],
    builder: _buildSanshan,
  );

  static const chenggu = AssistantToolDefinition(
    id: 'chenggu',
    title: '袁天罡称骨',
    description: '打开传统称骨计算；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['称骨', '袁天罡', '称骨算命'],
    actionWords: ['计算', '测算', '查询', '打开'],
    builder: _buildChenggu,
  );

  static const shoushengDebt = AssistantToolDefinition(
    id: 'shousheng_debt',
    title: '受生债查询',
    description: '查阅传统道教文献与民俗计算；不构成宗教或财务建议。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['受生债', '禄库受生经', '五斗金章'],
    actionWords: ['查询', '计算', '测算', '打开'],
    builder: _buildShoushengDebt,
  );

  static const huangdiSiji = AssistantToolDefinition(
    id: 'huangdi_siji',
    title: '轩辕黄帝四季歌',
    description: '打开传统四季歌查询；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['黄帝四季歌', '轩辕黄帝四季歌', '四季歌'],
    actionWords: ['查询', '查看', '测算', '打开'],
    builder: _buildHuangdiSiji,
  );

  static const savedCharts = AssistantToolDefinition(
    id: 'saved_charts',
    title: '我的命盘库',
    description: '查看已保存的生辰资料与命盘。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['我的命盘库', '保存的命盘', '已保存命盘'],
    actionWords: ['查看', '打开', '管理', '回看'],
    builder: _buildSavedCharts,
  );

  static const List<AssistantToolDefinition> _all = [
    structuredDiagnosis,
    yunqi,
    ziwei,
    bazi,
    yijing,
    xiaoliuren,
    meihua,
    dosage,
    ziwu,
    guji,
    medicalCases,
    almanac,
    diagnosisHistory,
    criticalIllness,
    solarTerms,
    yuxiaji,
    dream,
    guansha,
    sanshan,
    chenggu,
    shoushengDebt,
    huangdiSiji,
    savedCharts,
  ];

  static List<AssistantToolDefinition> get all =>
      List.unmodifiable(_all);

  static List<AssistantToolDefinition> quickActions(AssistantMode mode) =>
      _all.where((tool) => mode == AssistantMode.automatic || tool.modes.contains(mode)).toList(growable: false);

  /// Resolve a persisted tool action when a conversation is reopened.
  static AssistantToolDefinition? byId(String id) {
    for (final tool in _all) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  /// Match a short answer to a prior tool-type clarification. Unlike [match],
  /// this does not require an action verb; callers must require exactly one match.
  static List<AssistantToolDefinition> matchAliases(
    String query,
    AssistantMode mode,
  ) {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _all.where((tool) =>
      tool.modes.contains(mode) && tool.aliases.any(normalized.contains)
    ).toList(growable: false);
  }

  /// Return every explicit action match. Callers must clarify when more than
  /// one tool is named; silently selecting the first registry entry is unsafe.
  static List<AssistantToolDefinition> matchAll(
    String query,
    AssistantMode mode,
  ) {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    return _all.where((tool) {
      if (mode != AssistantMode.automatic && !tool.modes.contains(mode)) {
        return false;
      }
      return tool.aliases.any(normalized.contains) &&
          tool.actionWords.any(normalized.contains);
    }).toList(growable: false);
  }

  static AssistantToolDefinition? match(String query, AssistantMode mode) {
    final matches = matchAll(query, mode);
    return matches.length == 1 ? matches.single : null;
  }

  static Widget _buildStructuredDiagnosis() =>
      throw StateError(
        'Structured diagnosis must run inside LocalAiInterviewScreen; '
        'the legacy ChatScreen entry is disabled.',
      );
  static Widget _buildYunqi() => const YunQiScreen(returnResultOnComplete: true);
  static Widget _buildYunqiWithArguments(AssistantToolArguments arguments) {
    final rawDate = arguments['date'];
    final date = rawDate == null ? null : DateTime.tryParse(rawDate);
    return YunQiScreen(
      returnResultOnComplete: true,
      initialDate: date,
    );
  }
  static Widget _buildZiwei() =>
      const ZiweiChartScreen(returnResultOnComplete: true);
  static Widget _buildBazi() =>
      const BaZiPaipanScreen(returnResultOnComplete: true);
  static Widget _buildYijing() =>
      const YiJingScreen(returnResultOnComplete: true);
  static Widget _buildXiaoliuren() =>
      const XiaoliurenScreen(returnResultOnComplete: true);
  static Widget _buildMeihua() =>
      const MeihuaScreen(returnResultOnComplete: true);
  static Widget _buildDosage() =>
      const DosageConverterScreen(returnResultOnComplete: true);
  static Widget _buildZiwu() => const ZiWuLiuZhuScreen(returnResultOnComplete: true);
  static Widget _buildGuji() => const GujiLibraryScreen();
  static Widget _buildMedicalCases() => const MedicalCaseLibraryScreen();
  static Widget _buildAlmanac() =>
      const DailyAlmanacScreen(returnResultOnComplete: true);
  static Widget _buildDiagnosisHistory() => const DiagnosisHistoryScreen();
  static Widget _buildCriticalIllness() => const CriticalIllnessListScreen();
  static Widget _buildSolarTerms() => const SolarTermSectionScreen();
  static Widget _buildYuxiaji() => const YuxiajiOmenScreen();
  static Widget _buildDream() => const DreamScreen();
  static Widget _buildGuansha() => const GuanshaScreen();
  static Widget _buildSanshan() => const SanshanLingqianScreen();
  static Widget _buildChenggu() => const ChengguBoneScreen();
  static Widget _buildShoushengDebt() => const ShoushengDebtScreen();
  static Widget _buildHuangdiSiji() => const HuangdiSijiScreen();
  static Widget _buildSavedCharts() => const SavedChartsScreen();
}
