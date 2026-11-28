import '../screens/assistant_tool_router.dart';
import 'headless_tool_dispatcher.dart';

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
    if (candidates.any((tool) => !HeadlessToolDispatcher.hasExecutor(tool.id))) {
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

  static bool _isDosageConversionRequest(String query) {
    final hasQuantityAndUnit = RegExp(
      r'\d+(?:\.\d+)?\s*(两|铢|斤|石|钱|升|合|圭|撮|尺|寸)',
    ).hasMatch(query);
    final hasConversionAction = RegExp(
      r'(换算|转换|折合|换成|折为|多少克|多少毫升|多少厘米)',
    ).hasMatch(query);
    return hasQuantityAndUnit && hasConversionAction;
  }

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
    '教学',
    '课程',
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

  // General factual questions about a registered metaphysics domain should use
  // the metaphysics model prompt, not the TCM-only local knowledge retriever.
  // Explicit study, theory, and source-text requests remain in learning mode.
  static const _metaphysicsKnowledgeCues = [
    '什么是',
    '是什么',
    '分别是什么',
    '什么含义',
    '含义',
    '什么意思',
    '代表什么',
    '象征什么',
    '介绍一下',
    '讲讲',
    '解释',
    '怎么理解',
    '如何理解',
    '有什么区别',
    '区别是什么',
    '想了解',
    '了解一下',
    '学习',
    '系统学习',
    '教学',
    '课程',
    '概念',
    '原理',
    '历史背景',
    '发展史',
    '沿革',
    '原文',
    '出处',
    '条文',
    '属性',
    '五行',
    '方位',
    '吉凶',
  ];

  // A lone Xiaoliuren palace name is a metaphysics topic even when the
  // question has no generic learning cue such as “是什么” or “解释”.
  static const _xiaoliurenPalaceCues = [
    '大安',
    '留连',
    '速喜',
    '赤口',
    '小吉',
    '空亡',
  ];

  // Require a clear user action before allowing a knowledge question to enter
  // a deterministic metaphysics tool. Explaining a charting concept alone must
  // not be mistaken for a request to create a chart.
  static bool _hasExplicitMetaphysicsExecutionIntent(String text) {
    return RegExp(
      r'(?:请帮我|帮我|给我|我要|我想)(?:用.{1,8})?(?:排.{0,8}(?:盘|命盘)|起.{0,8}(?:卦|课)|推算|计算|算一下)',
    ).hasMatch(text) ||
        RegExp(
          r'(?:排.{0,8}(?:盘|命盘)|起.{0,8}(?:卦|课)|推算|计算|算一下)(?:并|然后|再|后)(?:解释|说明|分析|讲解)',
        ).hasMatch(text) ||
        const [
          '按时间起卦',
          '根据时间起卦',
          '按当前时间起卦',
        ].any(text.contains);
  }

  // These are ordinary intent-routing cues. They keep personal health narratives
  // out of metaphysics/tool-selection classification; they do not assess urgency
  // or create a clinical safety gate.
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
    '咽痛',
    '胸闷',
    '胸痛',
    '呼吸困难',
    '喘不上气',
    '意识障碍',
    '意识不清',
    '突发偏瘫',
    '偏瘫',
    '言语障碍',
    '说话不清',
    '大量出血',
    '自伤风险',
    '想伤害自己',
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

  static bool shouldExcludeFromIntentModel(String query) {
    final text = query.trim();
    return text.isNotEmpty &&
        (_symptomCues.any(text.contains) ||
            _personalContextCues.any(text.contains));
  }

  /// E4B may only help with a missing Bazi slot when the user's text
  /// contains a concrete cue for that field. Empty requests stay deterministic,
  /// and personal symptom narratives never enter this nonclinical extractor.
  static bool shouldUseBaziSlotModel(
    String query,
    Set<String> missingKeys,
  ) {
    final text = query.trim();
    if (text.isEmpty ||
        text.length > 2000 ||
        missingKeys.isEmpty ||
        _symptomCues.any(text.contains)) {
      return false;
    }
    if (missingKeys.contains('birth_date') &&
        !text.contains('农历') &&
        !text.contains('阴历') &&
        RegExp(
          r'\d{4}(?:年\d{1,2}月\d{1,2}[日号]?|[-/]\d{1,2}[-/]\d{1,2})',
        ).hasMatch(text)) {
      return true;
    }
    if (missingKeys.contains('birth_time') &&
        RegExp(
          r'(?:凌晨|清晨|早晨|早上|上午|中午|下午|傍晚|晚上)?\s*'
          r'[0-9零〇一二两三四五六七八九十]{1,3}(?:点|时)',
        ).hasMatch(text)) {
      return true;
    }
    if (missingKeys.contains('gender') &&
        text.contains('男') != text.contains('女')) {
      return true;
    }
    if (missingKeys.contains('birthplace') &&
        RegExp(
          r'(?:出生地|出生地点|出生于|出生在|生于|在[^，,。；;]{1,24}出生)',
        ).hasMatch(text)) {
      return true;
    }
    return false;
  }

  static AssistantToolArguments argumentsFor(
    AssistantToolDefinition tool,
    String query,
  ) {
    final values = <String, String>{};
    if (tool.id == 'shousheng_debt') {
      // The two local tables have different source-system conventions.
      // Never infer a method from an omitted choice or silently default to
      // the page's initial selection.
      final methods = <String>{
        if (query.contains('禄库受生经') ||
            query.contains('禄库受生') ||
            query.contains('禄库'))
          'luku',
        if (query.contains('五斗金章') || query.contains('五斗')) 'wudou',
      };
      if (methods.length == 1) {
        values['method'] = methods.single;
      } else if (methods.length > 1) {
        values['method'] = 'AMBIGUOUS_METHOD_SELECTION';
      }

      if (query.contains('农历') || query.contains('阴历')) {
        values['birth_date'] = 'LUNAR_DATE_NOT_SUPPORTED';
      } else {
        final dateMatches = <String>{};
        final isoDates = RegExp(
          r'(?<!\d)(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?!\d)',
        ).allMatches(query);
        final chineseDates = RegExp(
          r'(\d{4})年(\d{1,2})月(\d{1,2})日?',
        ).allMatches(query);
        for (final match in [...isoDates, ...chineseDates]) {
          dateMatches.add(
            match.group(1)!.padLeft(4, '0') + '-' +
                match.group(2)!.padLeft(2, '0') + '-' +
                match.group(3)!.padLeft(2, '0'),
          );
        }
        if (dateMatches.length == 1) {
          values['birth_date'] = dateMatches.single;
        } else if (dateMatches.length > 1) {
          values['birth_date'] = 'AMBIGUOUS_DATE_SELECTION';
        }
      }

      final timeMatches = RegExp(
        r'(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上)?\s*'
        r'(\d{1,2})(?::([0-5]\d)|(?:点|时)(?:(\d{1,2})分|半)?)',
      ).allMatches(query).map((match) {
        var hour = int.parse(match.group(2)!);
        final minute = match.group(3) != null
            ? int.parse(match.group(3)!)
            : match.group(4) != null
                ? int.parse(match.group(4)!)
                : match.group(0)!.contains('半')
                    ? 30
                    : 0;
        final period = match.group(1);
        if ((period == '下午' || period == '傍晚' || period == '晚上') &&
            hour >= 1 &&
            hour < 12) {
          hour += 12;
        } else if (period == '凌晨' && hour == 12) {
          hour = 0;
        }
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          return 'INVALID_TIME';
        }
        return hour.toString().padLeft(2, '0') + ':' +
            minute.toString().padLeft(2, '0');
      }).toSet();
      if (timeMatches.length == 1) {
        values['birth_time'] = timeMatches.single;
      } else if (timeMatches.length > 1) {
        values['birth_time'] = 'AMBIGUOUS_TIME_SELECTION';
      }
    } else if (tool.id == 'dream') {
      final marker = RegExp(r'(?:梦见|梦到|梦里有?|梦境(?:是|里)?|做梦(?:时)?)')
          .firstMatch(query);
      final detail = marker == null ? '' : query.substring(marker.end);
      final meaningfulDetail = detail.replaceAll(
        RegExp(r'(?:补充梦境细节|帮我|麻烦|请|解梦|解读|解释|分析|一下|什么意思|是什么意思|怎么理解|代表什么|一个|一条|一只|一群|很多|看到|看见|出现|我|是|被|有|了|的)'),
        '',
      ).replaceAll(RegExp(r'[，,。.!！?？；;：:、()（）“”"‘’·\s]+'), '');
      if (meaningfulDetail.isNotEmpty) {
        values['dream_text'] = query.trim();
      }
    } else if (tool.id == 'solar_terms') {
      final matches = AssistantToolRouter.solarTermNames
          .where(query.contains)
          .toList(growable: false);
      if (matches.length == 1) {
        values['term'] = matches.single;
      }
    } else if (tool.id == 'dosage') {
      const unitPattern = r'(两|铢|斤|石|钱|升|合|圭|撮|尺|寸)';
      final quantityUnitMatches = RegExp(
        r'(\d+(?:\.\d+)?)\s*' + unitPattern,
      ).allMatches(query).toList(growable: false);
      if (quantityUnitMatches.length == 1) {
        values['value'] = quantityUnitMatches.single.group(1)!;
        values['unit'] = quantityUnitMatches.single.group(2)!;
      } else if (quantityUnitMatches.length > 1) {
        values['unit'] = 'AMBIGUOUS_UNIT_SELECTION';
      } else {
        final value = RegExp(
          r'(?:数值|数量|换算数值|输入)\s*(?:是|为)?\s*[：:]?\s*(\d+(?:\.\d+)?)',
        ).firstMatch(query);
        final unit = RegExp(
          r'(?:原始单位|输入单位|单位)\s*(?:是|为)?\s*[：:]?\s*' + unitPattern,
        ).firstMatch(query);
        if (value != null) values['value'] = value.group(1)!;
        if (unit != null) values['unit'] = unit.group(1)!;
      }

      final standards = <String>[
        if (query.contains('汉制')) 'han',
        if (query.contains('台制')) 'taiwan',
        if (query.contains('唐制')) 'tang',
      ];
      if (standards.length == 1) {
        values['standard'] = standards.single;
      } else if (standards.length > 1) {
        values['standard'] = 'AMBIGUOUS_STANDARD_SELECTION';
      }
    } else if (tool.id == 'ziwu_liuzhu') {
      final isoDates = RegExp(
        r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
      ).allMatches(query).toList(growable: false);
      final chineseDates = RegExp(
        r'(\d{4})年(\d{1,2})月(\d{1,2})日?',
      ).allMatches(query).toList(growable: false);
      final dateValues = <String>{
        for (final match in [...isoDates, ...chineseDates])
          '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}',
      };
      if (dateValues.length == 1) {
        final date = dateValues.single;
        final parts = date.split('-').map(int.parse).toList(growable: false);
        final parsed = DateTime(parts[0], parts[1], parts[2]);
        values['date'] = parsed.year == parts[0] &&
                parsed.month == parts[1] &&
                parsed.day == parts[2] &&
                parts[0] >= 1900 &&
                parts[0] <= 2100
            ? date
            : 'INVALID_DATE';
      } else if (dateValues.length > 1) {
        values['date'] = 'AMBIGUOUS_DATE_SELECTION';
      }

      final timeMatches = RegExp(
        r'(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)',
      ).allMatches(query).toList(growable: false);
      final timeValues = timeMatches
          .map((match) =>
              '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}')
          .toSet();
      if (timeValues.length == 1) {
        values['time'] = timeValues.single;
      } else if (timeValues.length > 1) {
        values['time'] = 'AMBIGUOUS_TIME_SELECTION';
      } else if (RegExp(r'(\d{1,2}点|上午|下午|晚上|早上|凌晨|今晚|今早|午时|子时|酉时)')
          .hasMatch(query)) {
        values['time'] = 'UNPARSED_TIME';
      }
      if (dateValues.isEmpty &&
          RegExp(r'(\d{4}年|\d{4}[-/]|今天|明天|后天|昨天)')
              .hasMatch(query)) {
        values['date'] = 'UNPARSED_DATE';
      }
    } else if (tool.id == 'xiaoliuren') {
      final isoDates = RegExp(
        r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
      ).allMatches(query).toList(growable: false);
      final chineseDates = RegExp(
        r'(\d{4})年(\d{1,2})月(\d{1,2})日?',
      ).allMatches(query).toList(growable: false);
      final dateMatches = [...isoDates, ...chineseDates];
      final dates = dateMatches
          .map((match) =>
              '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}')
          .toSet();
      if (query.contains('农历') || query.contains('阴历')) {
        values['date'] = 'LUNAR_DATE_NOT_SUPPORTED';
      } else if (dates.length > 1) {
        values['date'] = 'AMBIGUOUS_DATE_SELECTION';
      } else if (dates.length == 1) {
        values['date'] = dates.single;
      } else if (dates.isEmpty &&
          (query.contains('今天') || query.contains('今日') ||
              query.contains('明天') || query.contains('明日') ||
              query.contains('昨天') || query.contains('昨日'))) {
        final offset =
            query.contains('明天') || query.contains('明日') ? 1 :
            query.contains('昨天') || query.contains('昨日') ? -1 : 0;
        final now = DateTime.now();
        final date = DateTime(now.year, now.month, now.day + offset);
        values['date'] = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      }
      final hours = AssistantToolRouter.xiaoliurenHourBranches
          .where(query.contains)
          .toList(growable: false);
      if (hours.length > 1) {
        values['hour'] = 'AMBIGUOUS_HOUR_SELECTION';
      } else if (hours.length == 1) {
        values['hour'] = hours.single;
      }
      final requestsDuoneng = query.contains('多能鄙事');
      final requestsCommon =
          query.contains('通行掌诀') || query.contains('通行口径');
      if (requestsDuoneng && requestsCommon) {
        values['rule'] = 'AMBIGUOUS_RULE_SELECTION';
      } else if (requestsDuoneng != requestsCommon) {
        values['rule'] = requestsDuoneng ? 'duoneng' : 'common';
      }
    } else if (tool.id == 'yijing') {
      final methods = <String>[];
      if (RegExp(r'(铜钱摇卦|摇铜钱|铜钱起卦)').hasMatch(query)) {
        methods.add('coins');
      }
      if (RegExp(r'(手动选卦|手动起卦|手动指定上下卦|静卦|动爻)').hasMatch(query) ||
          RegExp(r'(?:上卦|下卦)\s*(?:是|为)?\s*[：:]?\s*(?:乾|兑|離|离|震|巽|坎|艮|坤|[1-8])').hasMatch(query)) {
        methods.add('manual');
      }
      if (RegExp(r'(按当前时间.{0,6}起卦|当前时间起卦|按现在(?:的)?时间起卦|按当前时刻起卦|现在起卦|此刻起卦)').hasMatch(query)) {
        methods.add('time');
      }
      final numberPair = RegExp(
        r'(?:用|数字)?\s*(\d+)\s*(?:和|与|、|，|,)\s*(\d+)',
      ).firstMatch(query);
      if (query.contains('数字起卦') || query.contains('用数字') ||
          RegExp(r'(第一数|第二数|上卦数|下卦数)').hasMatch(query) ||
          numberPair != null) {
        methods.add('number');
      }
      final uniqueMethods = methods.toSet().toList(growable: false);
      if (uniqueMethods.length == 1) {
        values['method'] = uniqueMethods.single;
      } else if (uniqueMethods.length > 1) {
        values['method'] = 'AMBIGUOUS_METHOD_SELECTION';
      }

      if (uniqueMethods.contains('number')) {
        final first = RegExp(
          r'(?:第一数|上卦数)\s*(?:是|为)?\s*[：:]?\s*(\d+)',
        ).firstMatch(query);
        final second = RegExp(
          r'(?:第二数|下卦数)\s*(?:是|为)?\s*[：:]?\s*(\d+)',
        ).firstMatch(query);
        if (first != null) {
          values['first'] = first.group(1)!;
        }
        if (second != null) {
          values['second'] = second.group(1)!;
        }
        if ((first == null || second == null) && numberPair != null) {
          values['first'] ??= numberPair.group(1)!;
          values['second'] ??= numberPair.group(2)!;
        }
      } else if (uniqueMethods.contains('manual')) {
        String? trigramValue(RegExp expression) {
          final match = expression.firstMatch(query);
          if (match == null) return null;
          final raw = match.group(1)!;
          return AssistantToolRouter.yiJingTrigramNumbers[raw]?.toString() ?? raw;
        }

        final upper = trigramValue(RegExp(
          r'上卦\s*(?:是|为)?\s*[：:]?\s*(乾|兑|離|离|震|巽|坎|艮|坤|[1-8])',
        ));
        final lower = trigramValue(RegExp(
          r'下卦\s*(?:是|为)?\s*[：:]?\s*(乾|兑|離|离|震|巽|坎|艮|坤|[1-8])',
        ));
        if (upper != null) values['upper'] = upper;
        if (lower != null) values['lower'] = lower;
        if (query.contains('静卦') || query.contains('六爻皆静')) {
          values['moving'] = '0';
        } else {
          final moving = RegExp(
            r'(?:动爻\s*[：:]?\s*|第\s*)([0-6])\s*爻?(?:动)?',
          ).firstMatch(query);
          if (moving != null) values['moving'] = moving.group(1)!;
        }
      }
      // For time and coin modes, only the App injects the actual local clock
      // or six random outcomes at the execution boundary.
    } else if (tool.id == 'chenggu') {
      final isoDate = RegExp(
        r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b',
      ).firstMatch(query);
      final chineseDate =
          RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(query);
      final dateMatch = isoDate ?? chineseDate;
      if (query.contains('农历') || query.contains('阴历')) {
        values['birth_date'] = 'LUNAR_DATE_NOT_SUPPORTED';
      } else if (dateMatch != null) {
        values['birth_date'] =
            dateMatch.group(1)!.padLeft(4, '0') + '-' +
            dateMatch.group(2)!.padLeft(2, '0') + '-' +
            dateMatch.group(3)!.padLeft(2, '0');
      }

      // Parse the period before normalizing both clock and Chinese formats.
      // Otherwise "晚上8:30" would be mistaken for 08:30 because the old
      // colon-only branch discarded its period prefix.
      final timeMatch = RegExp(
        r'(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2})(?::([0-5]\d)|(?:点|时)(?:(\d{1,2})分|半)?)',
      ).firstMatch(query);
      if (timeMatch != null) {
        var hour = int.parse(timeMatch.group(2)!);
        final minute = timeMatch.group(3) != null
            ? int.parse(timeMatch.group(3)!)
            : timeMatch.group(4) != null
                ? int.parse(timeMatch.group(4)!)
                : timeMatch.group(0)!.contains('半')
                    ? 30
                    : 0;
        final period = timeMatch.group(1);
        if ((period == '下午' || period == '傍晚' || period == '晚上') &&
            hour >= 1 && hour < 12) {
          hour += 12;
        } else if (period == '凌晨' && hour == 12) {
          hour = 0;
        }
        if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
          values['birth_time'] =
              hour.toString().padLeft(2, '0') + ':' +
              minute.toString().padLeft(2, '0');
        }
      }
    } else if (tool.id == 'huangdi_siji') {
      final isoDate = RegExp(
        r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b',
      ).firstMatch(query);
      final chineseDate =
          RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(query);
      final dateMatch = isoDate ?? chineseDate;
      if (query.contains('农历') || query.contains('阴历')) {
        values['birth_date'] = 'LUNAR_DATE_NOT_SUPPORTED';
      } else if (dateMatch != null) {
        values['birth_date'] =
            dateMatch.group(1)!.padLeft(4, '0') + '-' +
            dateMatch.group(2)!.padLeft(2, '0') + '-' +
            dateMatch.group(3)!.padLeft(2, '0');
      }

      // Preserve explicit day-period semantics for both HH:mm and Chinese
      // clock input. No default date/time is introduced when a slot is absent.
      final timeMatch = RegExp(
        r'(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2})(?::([0-5]\d)|(?:点|时)(?:(\d{1,2})分|半)?)',
      ).firstMatch(query);
      if (timeMatch != null) {
        var hour = int.parse(timeMatch.group(2)!);
        final minute = timeMatch.group(3) != null
            ? int.parse(timeMatch.group(3)!)
            : timeMatch.group(4) != null
                ? int.parse(timeMatch.group(4)!)
                : timeMatch.group(0)!.contains('半')
                    ? 30
                    : 0;
        final period = timeMatch.group(1);
        if ((period == '下午' || period == '傍晚' || period == '晚上') &&
            hour >= 1 && hour < 12) {
          hour += 12;
        } else if (period == '凌晨' && hour == 12) {
          hour = 0;
        }
        if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
          values['birth_time'] =
              hour.toString().padLeft(2, '0') + ':' +
              minute.toString().padLeft(2, '0');
        }
      }
    } else if (tool.id == 'guansha') {
      // Guansha uses the same explicit birth-slot grammar as Bazi; reuse the
      // deterministic parser without invoking E4B or converting lunar dates.
      values.addAll(argumentsFor(AssistantToolRouter.bazi, query).values);
    } else if (tool.id == 'bazi') {

      final dateValues = <String>{
        for (final match in RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})')
            .allMatches(query))
          '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}',
        for (final match in RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日?')
            .allMatches(query))
          '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}',
      };
      final dateIsLunar = query.contains('农历') || query.contains('阴历');
      if (!dateIsLunar && dateValues.length > 1) {
        values['birth_date'] = 'AMBIGUOUS_DATE_SELECTION';
      } else if (!dateIsLunar && dateValues.length == 1) {
        values['birth_date'] = dateValues.single;
      }
      final timeValues = <String>{
        for (final match in RegExp(r'(\d{1,2}):(\d{2})').allMatches(query))
          '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}',
      };
      if (timeValues.length > 1) {
        values['birth_time'] = 'AMBIGUOUS_TIME_SELECTION';
      } else if (timeValues.length == 1) {
        values['birth_time'] = timeValues.single;
      }
      final hasMale = query.contains('男性') || query.contains('男');
      final hasFemale = query.contains('女性') || query.contains('女');
      if (hasMale != hasFemale) {
        values['gender'] = hasMale ? 'male' : 'female';
      }
      final birthplace = RegExp(
        r'出生(?:地点|地)?\s*[：:]\s*([^,，;；\n]+)',
      ).firstMatch(query);
      final place = birthplace?.group(1)?.trim();
      if (place != null && place.isNotEmpty) values['birthplace'] = place;
    } else if (tool.id == 'ziwei') {
      final dateValues = <String>{
        for (final match in RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})')
            .allMatches(query))
          '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}',
        for (final match in RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日?')
            .allMatches(query))
          '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}',
      };
      final dateIsLunar = query.contains('农历') || query.contains('阴历');
      if (dateIsLunar) {
        values['birth_date'] = 'LUNAR_DATE_NOT_SUPPORTED';
      } else if (dateValues.length > 1) {
        values['birth_date'] = 'AMBIGUOUS_DATE_SELECTION';
      } else if (dateValues.length == 1) {
        values['birth_date'] = dateValues.single;
      }
      final timeValues = <String>{
        for (final match in RegExp(r'(\d{1,2}):(\d{2})').allMatches(query))
          '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}',
      };
      if (timeValues.length > 1) {
        values['birth_time'] = 'AMBIGUOUS_TIME_SELECTION';
      } else if (timeValues.length == 1) {
        values['birth_time'] = timeValues.single;
      }
      final hasMale = query.contains('男性') || query.contains('男');
      final hasFemale = query.contains('女性') || query.contains('女');
      if (hasMale != hasFemale) {
        values['gender'] = hasMale ? 'male' : 'female';
      }
      final birthplace = RegExp(
        r'出生(?:地点|地)\s*[：:]\s*([^,，;；\n]+)',
      ).firstMatch(query);
      final place = birthplace?.group(1)?.trim();
      if (place != null && place.isNotEmpty) values['birthplace'] = place;
    } else if (tool.id == 'meihua') {
      final isTime = query.contains('时间起卦') || query.contains('按时间起卦');
      final isRandom = query.contains('随机起卦');
      final firstLabel =
          RegExp(r'(?:第一数|上卦数)\s*[：:]?\s*(\d{1,10})').firstMatch(query);
      final secondLabel =
          RegExp(r'(?:第二数|下卦数)\s*[：:]?\s*(\d{1,10})').firstMatch(query);
      final pair = firstLabel == null && secondLabel == null
          ? RegExp(
              r'(?:用|以)?\s*(\d{1,10})\s*(?:和|与|及|、|，|,)\s*(\d{1,10})',
            ).firstMatch(query)
          : null;

      // Method selection and simple slots are deterministic. Never infer a
      // number from an unrelated date, age, or other text.
      if (isTime) {
        values['method'] = 'time';
      } else if (isRandom) {
        values['method'] = 'random';
      } else if (query.contains('数字起卦') ||
          firstLabel != null ||
          secondLabel != null ||
          pair != null) {
        values['method'] = 'number';
      }
      if (firstLabel != null) values['first'] = firstLabel.group(1)!;
      if (secondLabel != null) values['second'] = secondLabel.group(1)!;
      if (pair != null) {
        values['first'] = pair.group(1)!;
        values['second'] = pair.group(2)!;
      }

      const branches = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
      final shouldCollectTime = values['method'] == 'time' ||
          values['method'] == null;
      String? explicitBranch;
      if (shouldCollectTime) {
        for (final branch in branches) {
          if (query.contains('${branch}时')) {
            explicitBranch = branch;
            break;
          }
        }
      }
      if (explicitBranch != null) {
        values['hour_branch'] = explicitBranch;
      } else if (shouldCollectTime) {
        final timeMatch = RegExp(
          r'(凌晨|清晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2})(?::([0-5]\d)|点)',
        ).firstMatch(query);
        if (timeMatch != null) {
          var hour = int.parse(timeMatch.group(2)!);
          final period = timeMatch.group(1);
          if ((period == '下午' || period == '傍晚' || period == '晚上') &&
              hour >= 1 && hour < 12) {
            hour += 12;
          } else if (period == '凌晨' && hour == 12) {
            hour = 0;
          }
          if (hour >= 0 && hour <= 23) {
            values['hour_branch'] = branches[((hour + 1) ~/ 2) % 12];
          }
        }
      }

      final isoDate = RegExp(
        r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b',
      ).firstMatch(query);
      final chineseDate =
          RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(query);
      if (query.contains('农历') || query.contains('阴历')) {
        // Preserve an explicit unsupported calendar basis as invalid input;
        // the caller must clarify instead of silently substituting today's date.
        values['date'] = 'LUNAR_DATE_NOT_SUPPORTED';
      } else if (isoDate != null) {
        values['date'] =
            '${isoDate.group(1)!.padLeft(4, '0')}-'
            '${isoDate.group(2)!.padLeft(2, '0')}-'
            '${isoDate.group(3)!.padLeft(2, '0')}';
      } else if (chineseDate != null) {
        values['date'] =
            '${chineseDate.group(1)}-${chineseDate.group(2)!.padLeft(2, '0')}-'
            '${chineseDate.group(3)!.padLeft(2, '0')}';
      } else if (query.contains('明天') || query.contains('明日') ||
          query.contains('昨天') || query.contains('昨日')) {
        final now = DateTime.now();
        final offset = query.contains('明天') || query.contains('明日') ? 1 : -1;
        final date = DateTime(now.year, now.month, now.day + offset);
        values['date'] = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      }
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
    bool hasStructuredKnowledgeEntity = false,
    bool hasKnowledgeRetrievalResult = false,
  }) {
    final text = query.trim();
    if (text.isEmpty) {
      return AssistantDispatchDecision(mode: selectedMode);
    }

    final explicitSolarTool =
        AssistantToolRouter.matchAll(text, selectedMode)
            .where((tool) => tool.id == 'solar_terms')
            .toList(growable: false);
    if (explicitSolarTool.length == 1) {
      final mentionedTerms = AssistantToolRouter.solarTermNames
          .where(text.contains)
          .toList(growable: false);
      if (mentionedTerms.length > 1) {
        return AssistantDispatchDecision(
          mode: selectedMode == AssistantMode.automatic
              ? AssistantMode.tools
              : selectedMode,
          clarification:
              '你同时提到了${mentionedTerms.join('、')}。一次只查询一个节气；请重新发送一个明确的节气名称，例如“查询立春养生”。尚未执行查询。',
        );
      }
      final asksForCurrentTerm = const [
        '当前节气',
        '今天的节气',
        '现在的节气',
      ].any(text.contains);
      if (mentionedTerms.isEmpty && !asksForCurrentTerm) {
        return AssistantDispatchDecision(
          mode: selectedMode == AssistantMode.automatic
              ? AssistantMode.tools
              : selectedMode,
          clarification:
              '请明确要查询哪一个节气；也可以说“查询当前节气”。目前尚未执行查询。',
        );
      }
    }

    final explicitXiaoliurenTools =
        AssistantToolRouter.matchAll(text, selectedMode)
            .where((tool) => tool.id == 'xiaoliuren')
            .toList(growable: false);
    if (explicitXiaoliurenTools.length == 1) {
      final isoDates = RegExp(
        r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
      ).allMatches(text).toList(growable: false);
      final chineseDates = RegExp(
        r'(\d{4})年(\d{1,2})月(\d{1,2})日?',
      ).allMatches(text).toList(growable: false);
      final dateValues = [...isoDates, ...chineseDates]
          .map((match) =>
              '${match.group(1)!.padLeft(4, '0')}-'
              '${match.group(2)!.padLeft(2, '0')}-'
              '${match.group(3)!.padLeft(2, '0')}')
          .toSet();
      final dateCount = dateValues.length;
      final hourCount = AssistantToolRouter.xiaoliurenHourBranches
          .where(text.contains)
          .length;
      final requestsDuoneng = text.contains('多能鄙事');
      final requestsCommon =
          text.contains('通行掌诀') || text.contains('通行口径');
      final ruleCount = requestsDuoneng || requestsCommon
          ? (requestsDuoneng ? 1 : 0) + (requestsCommon ? 1 : 0)
          : 0;
      if (dateCount > 1 || hourCount > 1 || ruleCount > 1) {
        return AssistantDispatchDecision(
          mode: selectedMode == AssistantMode.automatic
              ? AssistantMode.metaphysics
              : selectedMode,
          clarification: dateCount > 1
              ? '你提供了多个公历日期，请明确本次起课使用哪一天；尚未执行。'
              : hourCount > 1
                  ? '你提到了多个时辰，请明确选择一个时辰；尚未执行。'
                  : '你提到了两种起课口径，请明确选择通行掌诀或《多能鄙事》卷八口径；尚未执行。',
        );
      }
    }

    if (selectedMode != AssistantMode.automatic) {
      // The explicitly selected learning role is explanatory, not an execution
      // surface. A query such as “介绍医案检索方式” must not open the case page
      // merely because it contains a tool alias and an action word.
      if (selectedMode == AssistantMode.learning &&
          _learningCues.any(text.contains)) {
        return const AssistantDispatchDecision(mode: AssistantMode.learning);
      }
      if (selectedMode == AssistantMode.metaphysics &&
          (text.contains('梅花易数') || text.contains('梅花')) &&
          (text.contains('时间起卦') ||
              text.contains('按时间起卦') ||
              text.contains('随机起卦'))) {
        return AssistantDispatchDecision(
          mode: selectedMode,
          tool: AssistantToolRouter.meihua,
          toolArguments: argumentsFor(AssistantToolRouter.meihua, text),
        );
      }
      if (selectedMode == AssistantMode.tools &&
          _isDosageConversionRequest(text)) {
        return AssistantDispatchDecision(
          mode: selectedMode,
          tool: AssistantToolRouter.dosage,
          toolArguments: argumentsFor(AssistantToolRouter.dosage, text),
        );
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
      final explicitlyRequestsDiagnosis = RegExp(
        r'(帮我|请帮我|给我)(?:做|进行)?(?:个|一次)?(诊断|辨证)|诊断一下|辨证一下',
      ).hasMatch(text);
      if (explicitlyRequestsDiagnosis) {
        return AssistantDispatchDecision(
          mode: AssistantMode.consultation,
          tool: AssistantToolRouter.structuredDiagnosis,
          toolArguments: AssistantToolArguments(toolId: 'structured_diagnosis'),
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

    // Resolve a clear deterministic action before explanatory cues. This keeps
    // compound requests such as "please chart and explain" on the App tool path.
    final metaphysicsDomainMatches =
        AssistantToolRouter.matchAliases(text, AssistantMode.metaphysics);
    final hasMetaphysicsKnowledgeCue =
        _metaphysicsKnowledgeCues.any(text.contains);
    final isYunqiOnlyDomain =
        metaphysicsDomainMatches.isNotEmpty &&
        metaphysicsDomainMatches.every((tool) => tool.id == 'yunqi');
    final hasExplicitMetaphysicsExecutionIntent =
        _hasExplicitMetaphysicsExecutionIntent(text);

    if (metaphysicsDomainMatches.isNotEmpty &&
        hasMetaphysicsKnowledgeCue &&
        hasExplicitMetaphysicsExecutionIntent) {
      final explicitTools =
          AssistantToolRouter.matchAliases(text, AssistantMode.metaphysics);
      if (explicitTools.length == 1) {
        return AssistantDispatchDecision(
          mode: AssistantMode.metaphysics,
          tool: explicitTools.single,
          toolArguments: argumentsFor(explicitTools.single, text),
        );
      }
      if (explicitTools.length > 1) {
        return AssistantDispatchDecision(
          mode: AssistantMode.metaphysics,
          clarification:
              '你同时指定了多个术数工具（${explicitTools.map((tool) => tool.title).join('、')}），请先选择一个执行。',
          expectsToolSelection: true,
          candidateTools: _boundedCandidates(explicitTools),
        );
      }
    }

    // Pure metaphysics keywords must not fall through to Automatic mode merely
    // because a short factual question lacks a generic learning cue. Preserve
    // explicit tool execution and pending-tool-selection clarification, and keep
    // Five Movements and Six Qi in the TCM learning adapter.
    final pureMetaphysicsAliases = metaphysicsDomainMatches
        .where((tool) => tool.id != 'yunqi')
        .toList(growable: false);
    final mentionsXiaoliurenPalace =
        _xiaoliurenPalaceCues.any(text.contains);
    if ((pureMetaphysicsAliases.isNotEmpty || mentionsXiaoliurenPalace) &&
        !hasExplicitMetaphysicsExecutionIntent &&
        !pendingToolSelection) {
      return const AssistantDispatchDecision(mode: AssistantMode.metaphysics);
    }

    // Five Movements and Six Qi remains in the source-backed TCM learning
    // adapter. Other registered metaphysics knowledge questions use the
    // metaphysics model adapter, even when a prior tool choice is pending.
    if (metaphysicsDomainMatches.isNotEmpty && hasMetaphysicsKnowledgeCue) {
      return AssistantDispatchDecision(
        mode: isYunqiOnlyDomain
            ? AssistantMode.learning
            : AssistantMode.metaphysics,
      );
    }

    // Personal symptoms with explicit personal context outrank generic learning
    // wording in the same sentence (for example, "我最近咽痛，想了解桔梗汤").
    // Keep the turn in Consultation so the assistant asks whether it is a personal
    // health concern or a study question before treating it as general learning.
    if (_personalContextCues.any(text.contains) &&
        _symptomCues.any(text.contains)) {
      return const AssistantDispatchDecision(mode: AssistantMode.consultation);
    }

    // A pending tool selection is cancelled by an unrelated explicit learning
    // question; it must not force a non-Yunqi metaphysics topic into TCM retrieval.
    if (pendingToolSelection && _learningCues.any(text.contains)) {
      return const AssistantDispatchDecision(mode: AssistantMode.learning);
    }

    // Explicit learning/interpretation requests still take priority over
    // action words; this prevents “学习五运六气推算原理” from executing a tool.
    if (_learningCues.any(text.contains)) {
      return const AssistantDispatchDecision(mode: AssistantMode.learning);
    }
    if ((text.contains('梅花易数') || text.contains('梅花')) &&
        (text.contains('时间起卦') ||
            text.contains('按时间起卦') ||
            text.contains('随机起卦'))) {
      return AssistantDispatchDecision(
        mode: AssistantMode.metaphysics,
        tool: AssistantToolRouter.meihua,
        toolArguments: argumentsFor(AssistantToolRouter.meihua, text),
      );
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

    if (_isDosageConversionRequest(text)) {
      return AssistantDispatchDecision(
        mode: AssistantMode.tools,
        tool: AssistantToolRouter.dosage,
        toolArguments: argumentsFor(AssistantToolRouter.dosage, text),
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

      final explicitlyRequestsDiagnosis = RegExp(
        r'(帮我|请帮我|给我)(?:做|进行)?(?:个|一次)?(诊断|辨证)|诊断一下|辨证一下',
      ).hasMatch(text);
      if (explicitlyRequestsDiagnosis) {
        return AssistantDispatchDecision(
          mode: AssistantMode.consultation,
          tool: AssistantToolRouter.structuredDiagnosis,
          toolArguments: AssistantToolArguments(toolId: 'structured_diagnosis'),
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

    // A registered formula/herb/acupoint name and an actual source-backed
    // retrieval result must both be present before routing to Learning. An
    // entity name alone is not evidence that the local corpus has a usable hit.
    if (hasStructuredKnowledgeEntity && hasKnowledgeRetrievalResult) {
      return const AssistantDispatchDecision(mode: AssistantMode.learning);
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
