import '../screens/assistant_tool_router.dart';

/// A single-turn dispatch decision. The selected UI mode may remain automatic;
/// [mode] is the effective domain adapter for this turn.
class AssistantDispatchDecision {
  const AssistantDispatchDecision({
    required this.mode,
    this.tool,
    this.toolArguments,
    this.clarification,
    this.expectsToolSelection = false,
    this.candidateTools = const [],
  });

  final AssistantMode mode;
  final AssistantToolDefinition? tool;
  final AssistantToolArguments? toolArguments;
  final String? clarification;
  final bool expectsToolSelection;
  final List<AssistantToolDefinition> candidateTools;

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
  static List<AssistantToolDefinition> _boundedCandidates(
    Iterable<AssistantToolDefinition> tools,
  ) {
    final candidates = tools.toList(growable: false);
    if (candidates.length < 2 || candidates.length > 6) {
      return const [];
    }
    final ids = candidates.map((tool) => tool.id).toSet();
    if (ids.length != candidates.length) return const [];
    // E4B may only select capabilities that execute inside this conversation.
    // Page Tools remain deterministic clarifications until they gain a
    // validated Headless executor; never let model routing open another page.
    if (candidates.any((tool) => tool.headlessExecutor == null)) {
      return const [];
    }
    return List.unmodifiable(candidates);
  }

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
    '原理',
    '历史背景',
    '发展史',
    '沿革',
    '组成',
    '功效',
    '归经',
    '穴位定位',
    '病机',
  ];

  static const _symptomCues = [
    '头痛',
    '头晕',
    '不舒服',
    '难受',
    '不适',
    '疼痛',
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

  static bool containsPotentialHealthContent(String query) {
    final text = query.trim();
    return text.isNotEmpty && _symptomCues.any(text.contains);
  }

  static AssistantToolArguments argumentsFor(
    AssistantToolDefinition tool,
    String query,
  ) {
    final values = <String, String>{};
    if (tool.id == 'bazi') {
      final isoDate =
          RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(query);
      final chineseDate =
          RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(query);
      final dateMatch = isoDate ?? chineseDate;
      if (dateMatch != null) {
        values['birth_date'] =
            '${dateMatch.group(1)!.padLeft(4, '0')}-'
            '${dateMatch.group(2)!.padLeft(2, '0')}-'
            '${dateMatch.group(3)!.padLeft(2, '0')}';
      }
      final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(query);
      if (timeMatch != null) {
        values['birth_time'] =
            '${timeMatch.group(1)!.padLeft(2, '0')}:${timeMatch.group(2)}';
      }
      if (query.contains('女性') || query.contains('女')) {
        values['gender'] = 'female';
      } else if (query.contains('男性') || query.contains('男')) {
        values['gender'] = 'male';
      }
      final birthplace = RegExp(
        r'出生(?:地点|地)?\s*[：:]\s*([^,，;；\n]+)',
      ).firstMatch(query);
      final place = birthplace?.group(1)?.trim();
      if (place != null && place.isNotEmpty) values['birthplace'] = place;
    } else if (tool.id == 'yunqi' || tool.id == 'almanac') {
      final match = RegExp(r'\b\d{4}-\d{1,2}-\d{1,2}\b').firstMatch(query);
      if (match != null) {
        // Preserve the raw token; the execution boundary validates the actual
        // calendar date so invalid input cannot silently become another date.
        values['date'] = match.group(0)!;
      } else if (tool.id == 'almanac') {
        // Daily almanac defaults to the device's local calendar day.
        // Relative-day wording is resolved deterministically, without model inference.
        final now = DateTime.now();
        final offset = query.contains('明天') || query.contains('明日')
            ? 1
            : query.contains('昨天') || query.contains('昨日')
                ? -1
                : 0;
        final date = DateTime(now.year, now.month, now.day + offset);
        values['date'] = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      }
    }
    return AssistantToolArguments(toolId: tool.id, values: values);
  }

  static AssistantDispatchDecision resolve({
    required String query,
    required AssistantMode selectedMode,
    AssistantMode? currentMode,
    bool pendingToolSelection = false,
  }) {
    final text = query.trim();
    if (text.isEmpty) {
      return AssistantDispatchDecision(mode: selectedMode);
    }

    if (selectedMode != AssistantMode.automatic) {
      // The explicitly selected learning role is explanatory, not an execution
      // surface. A query such as “介绍医案检索方式” must not open the case page
      // merely because it contains a tool alias and an action word.
      if (selectedMode == AssistantMode.learning &&
          _learningCues.any(text.contains)) {
        return const AssistantDispatchDecision(mode: AssistantMode.learning);
      }
      final explicitMatches = AssistantToolRouter.matchAll(text, selectedMode);
      if (explicitMatches.length == 1) {
        return AssistantDispatchDecision(
          mode: selectedMode,
          tool: explicitMatches.single,
          toolArguments: argumentsFor(explicitMatches.single, text),
        );
      }
      if (explicitMatches.length > 1) {
        return AssistantDispatchDecision(
          mode: selectedMode,
          clarification:
              '你同时提出了多个工具（${explicitMatches.map((tool) => tool.title).join('、')}），请先选择一个执行。',
          expectsToolSelection: true,
          candidateTools: _boundedCandidates(explicitMatches),
        );
      }
      if (pendingToolSelection &&
          !_learningCues.any(text.contains) &&
          (selectedMode == AssistantMode.tools ||
              selectedMode == AssistantMode.metaphysics)) {
        final matches = AssistantToolRouter.matchAliases(text, selectedMode);
        if (matches.length == 1) {
          return AssistantDispatchDecision(
            mode: selectedMode,
            tool: matches.single,
            toolArguments: argumentsFor(matches.single, text),
          );
        }
        if (matches.length > 1) {
          return AssistantDispatchDecision(
            mode: selectedMode,
            clarification: '你提到了多个工具（${matches.map((tool) => tool.title).join('、')}），请只选择其中一个。',
            expectsToolSelection: true,
            candidateTools: _boundedCandidates(matches),
          );
        }
        return AssistantDispatchDecision(
          mode: selectedMode,
          clarification: selectedMode == AssistantMode.metaphysics
              ? '请明确选择工具：五运六气、紫微斗数、八字、易经、小六壬或梅花易数。'
              : '请明确说出要使用的 App 工具名称。',
          expectsToolSelection: true,
        );
      }
      if (!_learningCues.any(text.contains)) {
        if (selectedMode == AssistantMode.metaphysics &&
            (text.contains('排盘') || text.contains('排个盘') || text.contains('排一个盘') || text.contains('起卦') || text.contains('起课'))) {
          return AssistantDispatchDecision(
            mode: selectedMode,
            clarification: text.contains('排盘')
                ? '你想使用哪一种排盘工具：紫微斗数，还是八字四柱？'
                : '你想使用哪一种起卦工具：易经、小六壬，还是梅花易数？',
            expectsToolSelection: true,
            candidateTools: text.contains('排盘')
                ? _boundedCandidates([
                    AssistantToolRouter.ziwei,
                    AssistantToolRouter.bazi,
                  ])
                : _boundedCandidates([
                    AssistantToolRouter.yijing,
                    AssistantToolRouter.xiaoliuren,
                    AssistantToolRouter.meihua,
                  ]),
          );
        }
        if (selectedMode == AssistantMode.tools &&
            (text.contains('开穴') || text.contains('剂量换算'))) {
          return AssistantDispatchDecision(
            mode: AssistantMode.tools,
            clarification: '你想使用子午流注/时辰开穴工具，还是经方剂量换算工具？',
            expectsToolSelection: true,
            candidateTools: _boundedCandidates([
              AssistantToolRouter.ziwu,
              AssistantToolRouter.dosage,
            ]),
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
    if (pendingToolSelection &&
        _personalContextCues.any(text.contains) &&
        _symptomCues.any(text.contains)) {
      return const AssistantDispatchDecision(mode: AssistantMode.consultation);
    }
    if (pendingToolSelection &&
        ['取消', '算了', '先不排', '不用了'].any(text.contains)) {
      return AssistantDispatchDecision(
        mode: currentMode ?? AssistantMode.automatic,
      );
    }

    // A one-word answer such as “紫微” is meaningful only immediately after
    // the dispatcher has asked which tool the user wants. Keep the alias-only
    // path context-gated so ordinary mentions do not launch a calculator.
    if (pendingToolSelection &&
        (currentMode == AssistantMode.tools ||
            currentMode == AssistantMode.metaphysics)) {
      final mode = currentMode == AssistantMode.tools
          ? AssistantMode.tools
          : AssistantMode.metaphysics;
      final matches = AssistantToolRouter.matchAliases(text, mode);
      if (matches.length == 1) {
        return AssistantDispatchDecision(
          mode: mode,
          tool: matches.single,
          toolArguments: argumentsFor(matches.single, text),
        );
      }
      if (matches.length > 1) {
        return AssistantDispatchDecision(
          mode: mode,
          clarification: '你提到了多个工具（${matches.map((tool) => tool.title).join('、')}），请只选择其中一个。',
          expectsToolSelection: true,
          candidateTools: _boundedCandidates(matches),
        );
      }
      return AssistantDispatchDecision(
        mode: mode,
        clarification: mode == AssistantMode.metaphysics
            ? '请明确选择工具：五运六气、紫微斗数、八字、易经、小六壬或梅花易数。'
            : '请明确说出要使用的 App 工具名称。',
        expectsToolSelection: true,
      );
    }

    final explicitMatches =
        AssistantToolRouter.matchAll(text, AssistantMode.automatic);
    if (explicitMatches.length > 1) {
      final titles = explicitMatches.map((tool) => tool.title).join('、');
      final mode = explicitMatches.any(
        (tool) => tool.modes.contains(AssistantMode.metaphysics),
      )
          ? AssistantMode.metaphysics
          : AssistantMode.tools;
      return AssistantDispatchDecision(
        mode: mode,
        clarification: '你同时提出了多个工具（$titles），请先选择一个执行，避免只运行其中一项。',
        expectsToolSelection: true,
        candidateTools: _boundedCandidates(explicitMatches),
      );
    }
    if (explicitMatches.length == 1) {
      final tool = explicitMatches.single;
      final effectiveMode = tool.modes.contains(AssistantMode.metaphysics)
          ? AssistantMode.metaphysics
          : tool.modes.contains(AssistantMode.tools)
              ? AssistantMode.tools
              : AssistantMode.consultation;
      return AssistantDispatchDecision(
        mode: effectiveMode,
        tool: tool,
        toolArguments: argumentsFor(tool, text),
      );
    }

    if (text.contains('排盘') || text.contains('排个盘') || text.contains('命盘')) {
      return AssistantDispatchDecision(
        mode: AssistantMode.metaphysics,
        clarification: '你想使用哪一种排盘工具：紫微斗数，还是八字四柱？',
        expectsToolSelection: true,
        candidateTools: _boundedCandidates([
          AssistantToolRouter.ziwei,
          AssistantToolRouter.bazi,
        ]),
      );
    }
    if (text.contains('起卦') || text.contains('起课')) {
      return AssistantDispatchDecision(
        mode: AssistantMode.metaphysics,
        clarification: '你想使用哪一种起卦工具：易经、小六壬，还是梅花易数？',
        expectsToolSelection: true,
        candidateTools: _boundedCandidates([
          AssistantToolRouter.yijing,
          AssistantToolRouter.xiaoliuren,
          AssistantToolRouter.meihua,
        ]),
      );
    }
    if (text.contains('开穴') || text.contains('剂量换算')) {
      return AssistantDispatchDecision(
        mode: AssistantMode.tools,
        clarification: '你想使用子午流注/时辰开穴工具，还是经方剂量换算工具？',
        expectsToolSelection: true,
        candidateTools: _boundedCandidates([
          AssistantToolRouter.ziwu,
          AssistantToolRouter.dosage,
        ]),
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
