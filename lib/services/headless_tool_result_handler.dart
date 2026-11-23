import '../models/assistant_tool_result.dart';

enum HeadlessToolFollowUpKind {
  dreamClarification,
  birthplaceClarification,
}

/// A typed UI decision. The handler describes the next interaction; the
/// screen remains responsible for state mutation, persistence and rendering.
class HeadlessToolFollowUpIntent {
  const HeadlessToolFollowUpIntent({
    required this.kind,
    required this.toolId,
    required this.message,
  });

  final HeadlessToolFollowUpKind kind;
  final String toolId;
  final String message;
}

/// A validated, UI-ready interpretation of one deterministic tool result.
class HeadlessToolResultPresentation {
  const HeadlessToolResultPresentation({
    required this.contractErrors,
    required this.followUp,
    required this.responseText,
    required this.interpretationPrompt,
    required this.canInterpret,
    required this.autoInterpret,
    required this.toolStatusForPersistence,
    required this.argumentsForPersistence,
    required this.sourceIds,
  });

  final List<String> contractErrors;
  final HeadlessToolFollowUpIntent? followUp;
  final String responseText;
  final String interpretationPrompt;
  final bool canInterpret;
  final bool autoInterpret;
  final String toolStatusForPersistence;
  final Map<String, String> argumentsForPersistence;
  final List<String> sourceIds;

  bool get needsDreamFollowUp =>
      followUp?.kind == HeadlessToolFollowUpKind.dreamClarification;

  bool get needsBirthplaceFollowUp =>
      followUp?.kind == HeadlessToolFollowUpKind.birthplaceClarification;
}

/// Converts a deterministic Headless result into a typed presentation intent.
///
/// This class has no Flutter, Navigator, persistence, trace-recorder or widget
/// dependencies. It validates the result contract and prepares user-facing
/// text; the screen owns all state transitions and side effects.
class HeadlessToolResultHandler {
  const HeadlessToolResultHandler._();

  static HeadlessToolResultPresentation handle({
    required String userText,
    required String toolId,
    required String toolTitle,
    required Map<String, String> expectedArguments,
    required AssistantToolResult result,
    required bool aiReady,
  }) {
    final contractErrors = <String>[
      ...result.validateFor(toolId),
      ...result.validateArgumentsMatch(expectedArguments),
    ];
    if (contractErrors.isNotEmpty) {
      return HeadlessToolResultPresentation(
        contractErrors: List.unmodifiable(contractErrors),
        followUp: null,
        responseText: '',
        interpretationPrompt: '',
        canInterpret: false,
        autoInterpret: false,
        toolStatusForPersistence: result.statusLabel,
        argumentsForPersistence: Map.unmodifiable(expectedArguments),
        sourceIds: result.sourceIds,
      );
    }

    final needsDreamFollowUp = toolId == 'dream' &&
        (result.status == AssistantToolExecutionStatus.noResult ||
            result.values['检索状态'] == 'CANDIDATES_REQUIRE_CLARIFICATION');

    final unresolvedBirthplace =
        result.values['未执行原因']?.contains('无法唯一识别') == true;
    final needsBirthplaceFollowUp =
        (toolId == 'bazi' || toolId == 'ziwei' || toolId == 'guansha') &&
        result.status == AssistantToolExecutionStatus.failed &&
        unresolvedBirthplace;

    final followUp = needsBirthplaceFollowUp
        ? HeadlessToolFollowUpIntent(
            kind: HeadlessToolFollowUpKind.birthplaceClarification,
            toolId: toolId,
            message: switch (toolId) {
              'ziwei' => '本地城市目录无法唯一识别刚才的出生地点。请补充省/州和城市/区县的格式；本次没有执行紫微排盘。',
              'guansha' => '本地城市目录无法唯一识别刚才的出生地点。请补充省/州和城市/区县；没有使用默认地点，本次没有执行关煞测算。',
              _ => '本地城市目录无法唯一识别刚才的出生地点。请补充省/州和城市/区县的格式；本次没有执行八字排盘。',
            },
          )
        : needsDreamFollowUp
            ? HeadlessToolFollowUpIntent(
                kind: HeadlessToolFollowUpKind.dreamClarification,
                toolId: toolId,
                message: '',
              )
            : null;

    final responseText = followUp?.kind ==
            HeadlessToolFollowUpKind.birthplaceClarification
        ? followUp!.message
        : '【${toolTitle}执行结果】\\n${result.toConversationText()}';

    final canInterpret =
        result.status == AssistantToolExecutionStatus.succeeded &&
            result.sourceIds.isNotEmpty;
    final autoInterpret = canInterpret && aiReady;

    final interpretationPrompt = switch (toolId) {
      'saved_charts' =>
        '只解释 App 已根据用户明确选择的本地保存记录重新计算后返回的真实八字/紫微结果。'
            '先说明记录名称、记录 ID、排盘类型、保存的出生参数和本次使用的 App 设置。'
            '保存命盘存储的是出生资料与地点，不是历史结果快照；本次结果由 App 原有确定性引擎按当前设置重新计算。'
            '严格区分 App 计算字段与 AI 语言解释；不得改写四柱、宫位、星曜或其他计算字段，不补造缺失地点或参数。'
            '若地点字段显示 MISSING 或采用引擎默认地点，必须明确指出，不得描述为用户实际出生地。'
            '传统命理仅供文化学习参考，不是科学预测，不用于医疗、法律或投资决策。',
      'shousheng_debt' =>
        '请只解释 App 本地受生债数据表返回的实际字段和来源。'
            '这是传统道教文献与民俗表格的程序化查询，不代表现实中存在需要偿还的债务、欠款金额或法律/财务义务。'
            '严格区分禄库受生经与五斗金章两套表格，按 App 返回的查询体系和口径说明解释；若口径说明指出不同学术考订或民间流传版本有差异，必须保留差异，不自行选择、改写或合并口径。'
            '不得建议用户捐款、付款、购买供品、做法事或作出任何财务/宗教决定；不得将金额解释为现实债务或预测命运。'
            '只归纳 App 返回的出生参数、年支/日干/时支、对应表格数据、用途声明和来源，不重新排盘、不补造字段或出处。',
      'sanshan_lingqian' =>
        '请只解释 App 从本地三山国王祖庙传承 92 签签谱中返回的签号、签题、签诗、签级和签谱范围。'
            '先明确这是传统潮汕客家民间信仰与签谱文化文本，不是科学预测、事实保证或可以验证的未来信息；签级不代表现实一定吉或凶。'
            '只解释已返回签诗的字面意象、典故和文化表达，不补写签谱外的断语，不推断用户未来，不给医疗、法律、投资建议，也不鼓励用户据此作重大决定。'
            '区分 App 返回的原始签文与 AI 归纳，不得改签号、签级或伪造来源。',
      'guansha' =>
        '请只解释 App 本地关煞引擎返回的结构化字段和数据集原文。必须明确这属于传统民俗文化文本，不是科学事实、命运预测或医学判断。'
            '不得把关煞名称、儿童身体部位、犯者忌或化解文字解释为孩子患病、身体缺陷、寿命或健康风险；不得给出治疗、用药或就医替代建议，也不得鼓励因民俗结果采取惩罚、恐吓或限制儿童的做法。'
            '只总结已返回的实际出生参数、四柱、命中条目、规则依据和数据集范围；不重新排盘、不改写命中结果，不补造未返回的出处。',
      'bazi' =>
        '请结合用户原始请求“${userText}”，总结并解释刚才由 App 本地引擎返回的八字排盘结果。'
            '先概括本次实际出生参数和排盘口径，再解释四柱、十神、格局、强弱依据、五行状态和大运之间的关系。'
            '区分 App 本地引擎输出与 AI 归纳；不改动原始四柱，不补造缺失字段，也不把传统命理表述成科学预测。',
      'yuxiaji_omen' =>
        '请只解释 App 本地《玉匣记》数据表中与 App 本机时间对应的民俗文本。'
            '必须明确这是历史民俗文本，不是科学预测或现实事件保证，也不是医学诊断。'
            '不得把面热、眼跳、耳鸣、心惊、肉颤等条目解释为疾病、病因或健康风险，也不得给出治疗、用药或就医替代建议。'
            '只说明 App 返回的实际本机时间、时辰和原文条目；不得重新计算、改写时辰、补造其它占法或把民俗推断包装成事实。',
      'dream' =>
        '请解释刚才 App 本地梦境民俗数据集的检索结果。用户原始描述只是检索线索，不是事实证据。'
            '只归纳结果字段中的原文和候选差异，不补写数据集中不存在的释义，不把“吉/凶”等民俗标签说成现实预测或事实。'
            '若检索状态为 CANDIDATES_REQUIRE_CLARIFICATION，必须明确尚未选定匹配词条，只按数据集原始顺序简要列出候选，不得替用户挑选或排序，并只向用户追问一个能区分情节的问题。'
            '若为 SINGLE_MATCH，也必须说明这是本地民俗文本条目，不是科学结论或未来预言。不要给医疗、法律或投资建议。',
      _ =>
        '请根据本轮用户原始请求“${userText}”和下方已通过 App 结果契约校验的“'
            '${toolTitle}'
            '”执行结果，自动总结并解释实际输入、关键输出、字段含义、字段间关系和结果口径。'
            '明确区分 App 确定性计算/数据与 AI 的语言化归纳；缺失字段标记 MISSING，不猜算、不修改 App 返回值。'
            '只有在本地知识库返回了可引用条目时才结合该资料解释，并保留来源。',
    };

    return HeadlessToolResultPresentation(
      contractErrors: const [],
      followUp: followUp,
      responseText: responseText,
      interpretationPrompt: interpretationPrompt,
      canInterpret: canInterpret,
      autoInterpret: autoInterpret,
      toolStatusForPersistence: needsDreamFollowUp || needsBirthplaceFollowUp
          ? 'AWAITING_PARAMETERS'
          : result.statusLabel,
      argumentsForPersistence: Map.unmodifiable(
        needsBirthplaceFollowUp ? expectedArguments : result.arguments,
      ),
      sourceIds: result.sourceIds,
    );
  }
}
