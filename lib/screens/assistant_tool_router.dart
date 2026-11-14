import 'dart:async' show FutureOr;

import 'package:flutter/material.dart';

import '../models/assistant_tool_result.dart';
import '../services/yunqi_tool_executor.dart';
import '../services/almanac_tool_executor.dart';
import '../services/bazi_tool_executor.dart';
import '../services/meihua_tool_executor.dart';
import '../services/chenggu_tool_executor.dart';
import '../services/huangdi_siji_tool_executor.dart';
import '../services/ziwei_tool_executor.dart';
import '../services/solar_term_tool_executor.dart';
import '../services/xiaoliuren_tool_executor.dart';

import 'chenggu_bone_screen.dart';
import 'critical_illness_list_screen.dart';
import 'daily_almanac_screen.dart';
import 'diagnosis_history_screen.dart';
import 'dosage_converter_screen.dart';
import 'dream_screen.dart';
import 'guansha_screen.dart';
import 'guji_library_screen.dart';
import 'knowledge_screen.dart';
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
        AssistantMode.consultation => '围绕用户自述澄清症状。若历史中已有 App DiagnosticEngine 的结构化问诊结果，可以解释、归纳该结果并结合本地知识来源说明依据；不得自行新增或改写规则结论，不独立作个体诊断、处方或剂量建议。',
        AssistantMode.learning => '围绕中医知识学习；优先检索和引用 App 本地知识条目，基于命中资料做总结、比较、归纳和解释，指出共同点、差异、适用条件与来源分歧。明确区分课程讲稿、古籍文本、医案、App 结构化数据和 AI 归纳；讲稿观点不得冒充古籍原文，缺少依据或未检索到的内容标记 MISSING，不补造出处。',
        AssistantMode.tools => '实际计算必须由 App 已实现工具执行，不得猜算；工具结果返回对话后，基于返回字段做总结、归纳和解释，指出输入、结果、单位、来源及缺失项，并区分 App 确定性计算与 AI 解释。',
        AssistantMode.metaphysics => '解释八字、紫微等传统术数与民俗文化结果。排盘必须调用 App 内置工具；收到结果后，基于回传字段归纳结构、关系和时间层次，明确区分 App 确定性计算、App 规则模板与 AI 解释，不得重新排盘、篡改字段或补造缺失项。说明其非科学预测，不用于医疗、法律或投资决策。',
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

enum AssistantToolParameterType { text, date, time, integer, choice }

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
        case AssistantToolParameterType.time:
          if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(raw)) {
            errors.add('参数「' + parameter.label + '」必须使用 24 小时制 HH:mm');
          }
          break;
        case AssistantToolParameterType.integer:
          if (int.tryParse(raw) == null) {
            errors.add('参数「${parameter.label}」必须是整数');
          }
          break;
        case AssistantToolParameterType.choice:
          if (!parameter.choices.contains(raw)) {
            errors.add('参数「${parameter.label}」不在允许选项内');
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
  final FutureOr<AssistantToolResult> Function(Map<String, String> arguments)? headlessExecutor;
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
    this.headlessExecutor,
    this.parameters = const [],
  });
}

/// Deterministic intent-to-tool registry. A definition may expose a Page Tool,
/// a synchronous Headless executor, or both. Executed results remain typed and
/// are validated by the caller before they enter the conversation timeline.
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
    description: '使用 App 本地五运六气引擎直接推算；也可打开页面复核。',
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
    headlessExecutor: YunQiToolExecutor.execute,
  );

  static const ziwei = AssistantToolDefinition(
    id: 'ziwei',
    title: '紫微斗数排盘',
    description: '在当前对话收集明确的出生资料并调用 App 本地确定性紫微引擎；出生时间按出生地当地钟表时间输入，结果由 AI 进一步总结解释。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['紫微斗数', '紫微排盘', '紫微命盘'],
    actionWords: ['排盘', '起盘', '命盘', '帮我排'],
    builder: _buildZiwei,
    headlessExecutor: ZiweiToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'birth_date',
        label: '出生日期（公历）',
        type: AssistantToolParameterType.date,
        isRequired: true,
      ),
      AssistantToolParameter(
        key: 'birth_time',
        label: '出生时间',
        type: AssistantToolParameterType.time,
        isRequired: true,
        description: '出生地当地钟表时间，24 小时制 HH:mm',
      ),
      AssistantToolParameter(
        key: 'gender',
        label: '性别',
        type: AssistantToolParameterType.choice,
        isRequired: true,
        choices: ['male', 'female'],
      ),
      AssistantToolParameter(
        key: 'birthplace',
        label: '出生地点',
        type: AssistantToolParameterType.text,
        isRequired: true,
        description: '出生城市或区县，用于读取本地经纬度',
      ),
    ],
  );

  static const bazi = AssistantToolDefinition(
    id: 'bazi',
    title: '八字排盘',
    description: '在当前对话收集出生资料并调用 App 本地确定性八字引擎；出生时间按出生地当地钟表时间输入，结果由 AI 进一步总结解释。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['八字', '四柱', '生辰八字'],
    actionWords: ['排盘', '起盘', '命盘', '帮我排'],
    builder: _buildBazi,
    headlessExecutor: BaziToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'birth_date',
        label: '出生日期（公历）',
        type: AssistantToolParameterType.date,
        isRequired: true,
      ),
      AssistantToolParameter(
        key: 'birth_time',
        label: '出生时间',
        type: AssistantToolParameterType.time,
        isRequired: true,
        description: '出生地当地钟表时间，24 小时制 HH:mm',
      ),
      AssistantToolParameter(
        key: 'gender',
        label: '性别',
        type: AssistantToolParameterType.choice,
        isRequired: true,
        choices: ['male', 'female'],
      ),
      AssistantToolParameter(
        key: 'birthplace',
        label: '出生地点',
        type: AssistantToolParameterType.text,
        isRequired: true,
        description: '出生城市或区县，用于读取本地经纬度',
      ),
    ],
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
    description: '在当前对话收集公历日期和时辰，调用 App 原有小六壬纯函数；两种既有起课口径由用户明确选择。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['小六壬', '小六壬起课', '六壬时课'],
    actionWords: ['起课', '起卦', '推算', '算一下'],
    builder: _buildXiaoliuren,
    headlessExecutor: XiaoliurenToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'date',
        label: '公历日期',
        type: AssistantToolParameterType.date,
        isRequired: true,
      ),
      AssistantToolParameter(
        key: 'hour',
        label: '时辰',
        type: AssistantToolParameterType.choice,
        isRequired: true,
        choices: XiaoliurenToolExecutor.hourBranches,
      ),
      AssistantToolParameter(
        key: 'rule',
        label: '起课口径',
        type: AssistantToolParameterType.choice,
        description: '可选 common（通行掌诀，默认）或 duoneng（《多能鄙事》卷八）；两种口径并列，不把其中一种说成唯一传统。',
        isRequired: false,
        choices: ['common', 'duoneng'],
      ),
    ],
  );

  static const meihua = AssistantToolDefinition(
    id: 'meihua',
    title: '梅花易数起卦',
    description: '时间、数字和随机三种起卦均在当前对话中调用 App 原有本地算法。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['梅花易数', '梅花'],
    actionWords: ['起卦', '推算', '算一下'],
    builder: _buildMeihua,
    headlessExecutor: MeihuaToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'method',
        label: '起卦方式',
        type: AssistantToolParameterType.choice,
        isRequired: true,
        choices: ['number', 'time', 'random'],
      ),
      AssistantToolParameter(
        key: 'first',
        label: '第一数（上卦）',
        type: AssistantToolParameterType.integer,
      ),
      AssistantToolParameter(
        key: 'second',
        label: '第二数（下卦）',
        type: AssistantToolParameterType.integer,
      ),
      AssistantToolParameter(
        key: 'date',
        label: '公历起卦日期',
        type: AssistantToolParameterType.date,
      ),
      AssistantToolParameter(
        key: 'hour_branch',
        label: '时间起卦时辰',
        type: AssistantToolParameterType.choice,
        choices: ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'],
      ),
    ],
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

  static const knowledgeHub = AssistantToolDefinition(
    id: 'knowledge_hub',
    title: '中医知识库浏览',
    description: '打开 App 知识库浏览页；具体知识问答仍在当前统一会话中进行。',
    modes: {AssistantMode.learning},
    aliases: ['知识库', '中医知识库', '知识页面'],
    actionWords: ['打开', '浏览', '查看'],
    builder: _buildKnowledgeHub,
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
    description: '使用 App 本地黄历引擎计算指定日期；也可打开页面复核。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['黄历', '每日宜忌', '今日宜忌'],
    actionWords: ['查询', '查看', '打开', '今天'],
    parameters: [
      AssistantToolParameter(
        key: 'date',
        label: '查询日期',
        type: AssistantToolParameterType.date,
        isRequired: true,
        description: 'YYYY-MM-DD；由用户明确日期或“今日”语义解析。',
      ),
    ],
    builder: _buildAlmanac,
    headlessExecutor: AlmanacToolExecutor.execute,
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
    description: '在当前对话查询 App 已有节气计算结果及二十四节气知识资产；AI 只负责归纳和解释，不新增养生或个体医学结论。',
    modes: {AssistantMode.tools, AssistantMode.learning},
    aliases: [
      '节气养生',
      '二十四节气',
      '节气知识',
      '当前节气',
      '今天的节气',
      '现在的节气',
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
    ],
    actionWords: ['查询', '查看', '学习', '查阅', '打开', '介绍', '解释', '讲解', '比较', '对比'],
    builder: _buildSolarTerms,
    headlessExecutor: SolarTermToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'term',
        label: '目标节气',
        type: AssistantToolParameterType.choice,
        isRequired: false,
        description: '不指定时读取 App 当前节气；指定时从现有二十四节气知识资产检索。',
        choices: SolarTermToolExecutor.termNames,
      ),
    ],
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
    description: '在当前对话中收集明确的公历出生日期和当地钟表时间，复用 App 原有八字与称骨计算；仅供传统民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['称骨', '袁天罡', '称骨算命'],
    actionWords: ['计算', '测算', '查询', '打开', '帮我', '算一下'],
    builder: _buildChenggu,
    headlessExecutor: ChengguToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'birth_date',
        label: '出生日期（公历）',
        type: AssistantToolParameterType.date,
        isRequired: true,
      ),
      AssistantToolParameter(
        key: 'birth_time',
        label: '出生时间（当地钟表时间）',
        type: AssistantToolParameterType.time,
        isRequired: true,
        description: '24 小时制 HH:mm；缺失时必须向用户追问，不使用默认时间。',
      ),
    ],
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
    description: '在当前对话中收集明确的公历出生日期和当地钟表时间，复用 App 原有农历月份换算与本地四季歌数据；仅作民俗文化参考。',
    modes: {AssistantMode.tools, AssistantMode.metaphysics},
    aliases: ['黄帝四季歌', '轩辕黄帝四季歌', '四季歌'],
    actionWords: ['查询', '查看', '测算', '打开'],
    builder: _buildHuangdiSiji,
    headlessExecutor: HuangdiSijiToolExecutor.execute,
    parameters: [
      AssistantToolParameter(
        key: 'birth_date',
        label: '出生日期（公历）',
        type: AssistantToolParameterType.date,
        isRequired: true,
      ),
      AssistantToolParameter(
        key: 'birth_time',
        label: '出生时间（当地钟表时间）',
        type: AssistantToolParameterType.time,
        isRequired: true,
        description: '24 小时制 HH:mm；缺失时必须向用户追问，不使用页面默认时间。',
      ),
    ],
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
    knowledgeHub,
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
        'the legacy diagnosis entry is disabled.',
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
  static Widget _buildKnowledgeHub() => const KnowledgeScreen();
  static Widget _buildMedicalCases() => const MedicalCaseLibraryScreen();
  static Widget _buildAlmanac() =>
      const DailyAlmanacScreen(returnResultOnComplete: true);
  static Widget _buildDiagnosisHistory() => const DiagnosisHistoryScreen();
  static Widget _buildCriticalIllness() => const CriticalIllnessListScreen();
  static Widget _buildSolarTerms() => const SolarTermSectionScreen();
  static Widget _buildYuxiaji() => const YuxiajiOmenScreen();
  static Widget _buildDream() => const DreamScreen();
  static Widget _buildGuansha() => const GuanshaScreen(returnResultOnComplete: true);
  static Widget _buildSanshan() => const SanshanLingqianScreen(returnResultOnComplete: true);
  static Widget _buildChenggu() => const ChengguBoneScreen(returnResultOnComplete: true);
  static Widget _buildShoushengDebt() => const ShoushengDebtScreen(returnResultOnComplete: true);
  static Widget _buildHuangdiSiji() => const HuangdiSijiScreen(returnResultOnComplete: true);
  static Widget _buildSavedCharts() => const SavedChartsScreen();
}
