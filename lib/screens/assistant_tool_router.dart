import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'daily_almanac_screen.dart';
import 'dosage_converter_screen.dart';
import 'guji_library_screen.dart';
import 'medical_case_library_screen.dart';
import 'meihua_screen.dart';
import 'ziwei_chart_screen.dart';
import 'bazi_paipan_screen.dart';
import 'xiaoliuren_screen.dart';
import 'yijing_screen.dart';
import 'yunqi_screen.dart';
import 'ziwuliuzhu_screen.dart';

enum AssistantMode { automatic, consultation, learning, tools, metaphysics }

extension AssistantModePresentation on AssistantMode {
  String get label => switch (this) {
        AssistantMode.automatic => '自动调度',
        AssistantMode.consultation => '问诊助手',
        AssistantMode.learning => '学习助手',
        AssistantMode.tools => '工具助手',
        AssistantMode.metaphysics => '玄学助手',
      };

  String get promptHint => switch (this) {
        AssistantMode.automatic => '先识别任务领域；明确工具动作交给 App 工具，个人症状进入问诊，知识问题进入学习。意图不清时先澄清，不猜测。',
        AssistantMode.consultation => '围绕用户自述澄清症状，不替代规则辨证，不自动诊断或开方。',
        AssistantMode.learning => '围绕中医知识学习；优先引用 App 检索到的本地条目，缺少来源时明确标记 MISSING。',
        AssistantMode.tools => '只说明 App 已实现的工具能力；实际计算必须打开对应工具执行，不得猜算结果。',
        AssistantMode.metaphysics => '仅作民俗文化参考；明确说明非科学预测，不用于医疗、法律或投资决策。',
      };
}

class AssistantToolDefinition {
  final String id;
  final String title;
  final String description;
  final Set<AssistantMode> modes;
  final List<String> aliases;
  final List<String> actionWords;
  final Widget Function() builder;

  const AssistantToolDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.modes,
    required this.aliases,
    required this.actionWords,
    required this.builder,
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
    modes: {AssistantMode.tools},
    aliases: ['五运六气', '运气推算', '岁运司天在泉'],
    actionWords: ['推算', '计算', '算一下', '起算', '帮我算'],
    builder: _buildYunqi,
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
  ];

  static List<AssistantToolDefinition> quickActions(AssistantMode mode) =>
      _all.where((tool) => mode == AssistantMode.automatic || tool.modes.contains(mode)).toList(growable: false);

  static AssistantToolDefinition? match(String query, AssistantMode mode) {
    final normalized = query.trim();
    if (normalized.isEmpty) return null;
    for (final tool in _all) {
      if (mode != AssistantMode.automatic && !tool.modes.contains(mode)) continue;
      if (!tool.aliases.any(normalized.contains)) continue;
      if (!tool.actionWords.any(normalized.contains)) continue;
      return tool;
    }
    return null;
  }

  static Widget _buildStructuredDiagnosis() =>
      const ChatScreen(returnResultOnComplete: true);
  static Widget _buildYunqi() => const YunQiScreen(returnResultOnComplete: true);
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
  static Widget _buildDosage() => const DosageConverterScreen();
  static Widget _buildZiwu() => const ZiWuLiuZhuScreen();
  static Widget _buildGuji() => const GujiLibraryScreen();
  static Widget _buildMedicalCases() => const MedicalCaseLibraryScreen();
  static Widget _buildAlmanac() => const DailyAlmanacScreen();
}
