import '../screens/assistant_tool_router.dart';

/// A single-turn dispatch decision. The selected UI mode may remain automatic;
/// [mode] is the effective domain adapter for this turn.
class AssistantDispatchDecision {
  const AssistantDispatchDecision({
    required this.mode,
    this.tool,
    this.clarification,
  });

  final AssistantMode mode;
  final AssistantToolDefinition? tool;
  final String? clarification;

  bool get needsClarification => clarification != null;
  bool get launchesTool => tool != null;
}

/// Deterministic first-pass dispatcher for the unified assistant.
///
/// Explicit tool actions are resolved before domain classification. Personal
/// symptom narratives go to consultation, educational questions go to local
/// knowledge retrieval, and symptom-only ambiguous phrases are clarified.
/// This is intentionally rule-based: it does not claim model confidence or
/// silently execute an uncertain tool call.
class AssistantConversationOrchestrator {
  static const _personalContextCues = [
    '我最近',
    '我这几天',
    '我今天',
    '我现在',
    '我出现',
    '我有',
    '我感觉',
    '我的症状',
    '帮我看看',
    '帮我分析',
    '我身体',
  ];

  static const _learningCues = [
    '什么是',
    '是什么',
    '介绍一下',
    '讲讲',
    '解释',
    '怎么理解',
    '如何理解',
    '有什么区别',
    '区别是什么',
    '原文',
    '出处',
    '条文',
    '学习',
    '想了解',
    '了解一下',
    '概念',
    '理论',
    '组成',
    '功效',
    '归经',
    '穴位定位',
    '病机',
  ];

  static const _symptomCues = [
    '头痛',
    '头晕',
    '发热',
    '恶寒',
    '咳嗽',
    '胸闷',
    '胸痛',
    '腹痛',
    '腹胀',
    '腹泻',
    '便秘',
    '口苦',
    '口干',
    '失眠',
    '心悸',
    '乏力',
    '恶心',
    '呕吐',
    '尿频',
    '尿痛',
    '关节痛',
    '出汗',
    '怕冷',
    '怕热',
  ];

  static AssistantDispatchDecision resolve({
    required String query,
    required AssistantMode selectedMode,
    AssistantMode? currentMode,
  }) {
    final text = query.trim();
    if (text.isEmpty) {
      return AssistantDispatchDecision(mode: selectedMode);
    }

    if (selectedMode != AssistantMode.automatic) {
      final tool = AssistantToolRouter.match(text, selectedMode);
      if (tool != null) {
        return AssistantDispatchDecision(mode: selectedMode, tool: tool);
      }
      if (currentMode == selectedMode &&
          !_learningCues.any(text.contains) &&
          (selectedMode == AssistantMode.tools ||
              selectedMode == AssistantMode.metaphysics)) {
        final matches = AssistantToolRouter.matchAliases(text, selectedMode);
        if (matches.length == 1) {
          return AssistantDispatchDecision(mode: selectedMode, tool: matches.single);
        }
        if (matches.length > 1) {
          return AssistantDispatchDecision(
            mode: selectedMode,
            clarification: '你提到了多个工具（${matches.map((tool) => tool.title).join('、')}），请只选择其中一个。',
          );
        }
      }
      return AssistantDispatchDecision(mode: selectedMode);
    }

    // 明确的学习/解释请求优先于工具名和动作词，避免“学习五运六气推算原理”
    // 被误路由成实际计算。用户明确选择工具角色时仍尊重手动模式。
    if (_learningCues.any(text.contains)) {
      return const AssistantDispatchDecision(mode: AssistantMode.learning);
    }

    // A one-word answer such as “紫微” is meaningful only immediately after
    // the dispatcher has asked which tool the user wants. Keep the alias-only
    // path context-gated so ordinary mentions do not launch a calculator.
    if (currentMode == AssistantMode.tools ||
        currentMode == AssistantMode.metaphysics) {
      final matches = AssistantToolRouter.matchAliases(text, currentMode!);
      if (matches.length == 1) {
        return AssistantDispatchDecision(mode: currentMode, tool: matches.single);
      }
      if (matches.length > 1) {
        return AssistantDispatchDecision(
          mode: currentMode,
          clarification: '你提到了多个工具（${matches.map((tool) => tool.title).join('、')}），请只选择其中一个。',
        );
      }
    }

    final tool = AssistantToolRouter.match(text, AssistantMode.automatic);
    if (tool != null) {
      final effectiveMode = tool.modes.contains(AssistantMode.metaphysics)
          ? AssistantMode.metaphysics
          : tool.modes.contains(AssistantMode.tools)
              ? AssistantMode.tools
              : AssistantMode.consultation;
      return AssistantDispatchDecision(mode: effectiveMode, tool: tool);
    }

    if (text.contains('排盘') || text.contains('排个盘') || text.contains('命盘')) {
      return const AssistantDispatchDecision(
        mode: AssistantMode.metaphysics,
        clarification: '你想使用哪一种排盘工具：紫微斗数，还是八字四柱？',
      );
    }
    if (text.contains('起卦') || text.contains('起课')) {
      return const AssistantDispatchDecision(
        mode: AssistantMode.metaphysics,
        clarification: '你想使用哪一种起卦工具：易经、小六壬，还是梅花易数？',
      );
    }
    if (text.contains('开穴') || text.contains('剂量换算')) {
      return const AssistantDispatchDecision(
        mode: AssistantMode.tools,
        clarification: '你想使用子午流注/时辰开穴工具，还是经方剂量换算工具？',
      );
    }

    final hasSymptoms = _symptomCues.any(text.contains);
    final hasPersonalContext = _personalContextCues.any(text.contains);
    if (hasSymptoms && hasPersonalContext) {
      return const AssistantDispatchDecision(mode: AssistantMode.consultation);
    }

    if (_learningCues.any(text.contains)) {
      return const AssistantDispatchDecision(mode: AssistantMode.learning);
    }

    if (hasSymptoms && text.startsWith('我')) {
      return const AssistantDispatchDecision(mode: AssistantMode.consultation);
    }

    if (hasSymptoms) {
      if (currentMode == AssistantMode.consultation) {
        return const AssistantDispatchDecision(mode: AssistantMode.consultation);
      }
      if (currentMode == AssistantMode.learning) {
        return const AssistantDispatchDecision(mode: AssistantMode.learning);
      }
      return const AssistantDispatchDecision(
        mode: AssistantMode.consultation,
        clarification: '你提到了具体症状。请确认：这是你本人目前的情况，还是想学习该症状的中医理论？',
      );
    }

    // No new explicit intent: continue the active domain for short answers and
    // follow-up questions instead of silently switching roles every turn.
    return AssistantDispatchDecision(
      // A new, unclassified conversation remains in automatic/general mode.
      // Do not silently label ordinary chat as TCM learning.
      mode: currentMode ?? AssistantMode.automatic,
    );
  }
}
