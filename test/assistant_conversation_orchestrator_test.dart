import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/assistant_conversation_orchestrator.dart';

void main() {
  group('统一助手自动调度', () {
    test('普通寒暄和一般聊天保持自动/通用助手，不强行归类为学习', () {
      for (final query in ['你好', '你能做什么？', '今天有什么值得聊的？']) {
        final decision = AssistantConversationOrchestrator.resolve(
          query: query,
          selectedMode: AssistantMode.automatic,
        );
        expect(decision.mode, AssistantMode.automatic, reason: query);
        expect(decision.tool, isNull, reason: query);
        expect(decision.needsClarification, isFalse, reason: query);
      }
    });

    test('个人症状文本被识别为健康叙述，不进入工具意图模型', () {
      expect(
        AssistantConversationOrchestrator.shouldExcludeFromIntentModel(
          '我最近三天口苦，帮我排个盘',
        ),
        isTrue,
      );
      expect(
        AssistantConversationOrchestrator.shouldExcludeFromIntentModel(
          '我最近不舒服，帮我排个盘',
        ),
        isTrue,
      );
      expect(
        AssistantConversationOrchestrator.shouldExcludeFromIntentModel(
          '我有呼吸困难，帮我起卦',
        ),
        isTrue,
        reason: '个人健康叙述即使不含当前显式症状别名，也不进入工具意图模型',
      );
      expect(
        AssistantConversationOrchestrator.shouldExcludeFromIntentModel(
          '帮我排个盘',
        ),
        isFalse,
      );
    });

    test('个人症状叙述进入问诊助手', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '我最近三天口苦，睡眠不好，半夜容易醒',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.consultation);
      expect(decision.tool, isNull);
      expect(decision.needsClarification, isFalse);
    });

    test('中医概念和经典条文问题进入学习助手', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '《伤寒论》第172条原文和黄芩汤的关系是什么？',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.tool, isNull);
    });

    test('工具澄清后补充的日期仍进入五运六气 typed arguments', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '五运六气 2026-11-06',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
        pendingToolSelection: true,
      );
      expect(decision.tool?.id, 'yunqi');
      expect(decision.toolArguments?['date'], '2026-11-06');
    });

    test('玄学工具澄清后的原理问题仍进入学习，不启动计算器', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '五运六气推算原理',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
        pendingToolSelection: true,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.tool, isNull);
    });

    test('学习五运六气推算原理进入学习助手，不启动计算器', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '学习五运六气推算原理',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.tool, isNull);
    });

    test('介绍医案检索方式进入学习助手，不直接打开资料页', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '介绍一下医案检索的方式',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.tool, isNull);
    });

    test('明确工具动作自动路由五运六气', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我推算五运六气',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.metaphysics);
      expect(decision.tool?.id, 'yunqi');
    });

    test('五运六气请求中的日期进入 typed tool arguments', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我推算五运六气，日期 2026-11-06',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.tool?.id, 'yunqi');
      expect(decision.toolArguments?.toolId, 'yunqi');
      expect(decision.toolArguments?['date'], '2026-11-06');
    });

    test('每日黄历明确日期进入 Headless 参数，非法日期原样保留待拒绝', () {
      final valid = AssistantConversationOrchestrator.resolve(
        query: '帮我查询黄历 2026-11-12',
        selectedMode: AssistantMode.automatic,
      );
      expect(valid.tool?.id, 'almanac');
      expect(valid.toolArguments?['date'], '2026-11-12');

      final invalid = AssistantConversationOrchestrator.resolve(
        query: '帮我查询黄历 2026-02-30',
        selectedMode: AssistantMode.automatic,
      );
      expect(invalid.tool?.id, 'almanac');
      expect(invalid.toolArguments?['date'], '2026-02-30');
      expect(invalid.toolArguments!.validateAgainst(invalid.tool!), isNotEmpty);
    });

    test('今日与明日黄历使用设备本地日期，不依赖模型推断', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      String iso(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      final todayDecision = AssistantConversationOrchestrator.resolve(
        query: '查询今日黄历',
        selectedMode: AssistantMode.automatic,
      );
      final tomorrowDecision = AssistantConversationOrchestrator.resolve(
        query: '查看明天黄历',
        selectedMode: AssistantMode.automatic,
      );
      expect(todayDecision.tool?.id, 'almanac');
      expect(todayDecision.toolArguments?['date'], iso(today));
      expect(tomorrowDecision.tool?.id, 'almanac');
      expect(tomorrowDecision.toolArguments?['date'], iso(tomorrow));
    });

    test('玄学助手模式下也能直接调度五运六气计算器', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '推算五运六气',
        selectedMode: AssistantMode.metaphysics,
      );
      expect(decision.mode, AssistantMode.metaphysics);
      expect(decision.tool?.id, 'yunqi');
    });

    test('明确排盘动作自动进入玄学工具域', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我排八字',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.metaphysics);
      expect(decision.tool?.id, 'bazi');
    });

    test('八字请求在对话中抽取出生参数并校验完整性', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我排八字',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.tool?.id, 'bazi');
      expect(decision.toolArguments?.values, isEmpty);

      final parsed = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.bazi,
        '出生日期：1990年1月2日；出生时间：08:30；性别：男；出生地：上海市',
      );
      expect(parsed.values, const {
        'birth_date': '1990-01-02',
        'birth_time': '08:30',
        'gender': 'male',
        'birthplace': '上海市',
      });
      expect(parsed.validateAgainst(AssistantToolRouter.bazi), isEmpty);

      final invalid = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.bazi,
        '出生日期：1990-02-31；出生时间：25:70；性别：女；出生地：朝阳',
      );
      final errors = invalid.validateAgainst(AssistantToolRouter.bazi);
      expect(errors.join('；'), contains('出生日期'));
      expect(errors.join('；'), contains('出生时间'));
      expect(invalid['gender'], 'female');
      expect(invalid['birthplace'], '朝阳');
    });

    test('八字槽位模型只在缺失字段有明确线索时调用', () {
      expect(
        AssistantConversationOrchestrator.shouldUseBaziSlotModel(
          '帮我排八字',
          const {'birth_date', 'birth_time', 'gender', 'birthplace'},
        ),
        isFalse,
      );
      expect(
        AssistantConversationOrchestrator.shouldUseBaziSlotModel(
          '我在上海市出生，早上八点半，帮我排八字',
          const {'birth_time', 'birthplace'},
        ),
        isTrue,
      );
      expect(
        AssistantConversationOrchestrator.shouldUseBaziSlotModel(
          '我最近三天口苦，早上八点半，在上海市出生，帮我排八字',
          const {'birth_time', 'birthplace'},
        ),
        isFalse,
        reason: '个人症状叙述不得进入非医疗术数参数抽取模型',
      );
    });

    test('八字自然语言中男女信息冲突时不确定性别', () {
      final parsed = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.bazi,
        '出生日期：1990-01-02；出生时间：08:30；可能是男也可能是女；出生地：上海市',
      );
      expect(parsed['gender'], isNull);
      expect(
        parsed.validateAgainst(AssistantToolRouter.bazi),
        contains(contains('性别')),
      );
    });

    test('八字出生日期支持常见中文公历格式', () {
      final parsed = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.bazi,
        '1990年1月2日，时间 8:30，男性，出生地：上海市',
      );
      expect(parsed['birth_date'], '1990-01-02');
      expect(parsed['birth_time'], '08:30');
      expect(parsed['gender'], 'male');
    });

    test('没有个人语境的单独症状先澄清，不擅自问诊', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '头痛',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.needsClarification, isTrue);
      expect(decision.clarification, contains('本人目前的情况'));
      expect(decision.tool, isNull);
    });

    test('问诊中的简短追问沿用问诊角色', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '三天',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.consultation,
      );
      expect(decision.mode, AssistantMode.consultation);
      expect(decision.needsClarification, isFalse);
    });

    test('学习中的追问沿用学习角色', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '为什么',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.learning,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.needsClarification, isFalse);
    });

    test('明确的知识问题可以从问诊角色切换到学习角色', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '口苦是什么',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.consultation,
      );
      expect(decision.mode, AssistantMode.learning);
    });

    test('手动学习模式中的工具相关解释请求不启动工具页面', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '介绍一下医案检索的方式',
        selectedMode: AssistantMode.learning,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.tool, isNull);
      expect(decision.needsClarification, isFalse);
    });

    test('用户明确选择角色时尊重手动模式，不擅自改派', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '介绍一下五运六气',
        selectedMode: AssistantMode.consultation,
      );
      expect(decision.mode, AssistantMode.consultation);
      expect(decision.tool, isNull);
    });

    test('没有指定类型的排盘请求先询问工具类型', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我排个盘',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.needsClarification, isTrue);
      expect(decision.clarification, contains('紫微斗数'));
      expect(decision.clarification, contains('八字四柱'));
    });

    test('排盘澄清生成受限的紫微/八字候选集', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我排个盘',
        selectedMode: AssistantMode.automatic,
      );

      expect(decision.needsClarification, isTrue);
      expect(
        decision.candidateTools,
        isEmpty,
        reason: '紫微仍是 Page Tool，不能交给 E4B 自动选择并导航',
      );
    });

    test('起卦澄清生成不超过六项的候选集', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我起卦',
        selectedMode: AssistantMode.automatic,
      );

      expect(decision.needsClarification, isTrue);
      expect(
        decision.candidateTools,
        isEmpty,
        reason: '易经/小六壬/梅花当前仍是 Page Tool',
      );
    });

    test('只有全部具备 Headless 执行器的候选集才交给 E4B', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '推算五运六气，并查询黄历',
        selectedMode: AssistantMode.metaphysics,
      );

      expect(decision.needsClarification, isTrue);
      expect(
        decision.candidateTools.map((tool) => tool.id),
        ['yunqi', 'almanac'],
      );
      expect(
        decision.candidateTools.every((tool) => tool.headlessExecutor != null),
        isTrue,
      );
    });

    test('问诊和学习路由不生成工具候选，避免送入工具意图判别器', () {
      final consultation = AssistantConversationOrchestrator.resolve(
        query: '我最近三天口苦，睡眠不好',
        selectedMode: AssistantMode.automatic,
      );
      final learning = AssistantConversationOrchestrator.resolve(
        query: '讲讲《伤寒论》的历史背景',
        selectedMode: AssistantMode.automatic,
      );

      expect(consultation.mode, AssistantMode.consultation);
      expect(consultation.candidateTools, isEmpty);
      expect(learning.mode, AssistantMode.learning);
      expect(learning.candidateTools, isEmpty);
    });

    test('没有指定体系的起卦请求先询问工具类型', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我起卦',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.needsClarification, isTrue);
      expect(decision.clarification, contains('易经'));
      expect(decision.clarification, contains('小六壬'));
      expect(decision.clarification, contains('梅花易数'));
    });


    test('排盘澄清后仅回答工具名称即可进入对应排盘工具', () {
      final first = AssistantConversationOrchestrator.resolve(
        query: '帮我排个盘',
        selectedMode: AssistantMode.automatic,
      );
      expect(first.needsClarification, isTrue);
      expect(first.expectsToolSelection, isTrue);

      final answer = AssistantConversationOrchestrator.resolve(
        query: '紫微斗数',
        selectedMode: AssistantMode.automatic,
        currentMode: first.mode,
        pendingToolSelection: first.expectsToolSelection,
      );
      expect(answer.mode, AssistantMode.metaphysics);
      expect(answer.tool?.id, 'ziwei');
      expect(answer.needsClarification, isFalse);
    });

    test('起卦澄清后可识别短答案，多个工具答案继续澄清', () {
      final first = AssistantConversationOrchestrator.resolve(
        query: '帮我起卦',
        selectedMode: AssistantMode.automatic,
      );
      expect(first.expectsToolSelection, isTrue);
      final answer = AssistantConversationOrchestrator.resolve(
        query: '小六壬',
        selectedMode: AssistantMode.automatic,
        currentMode: first.mode,
        pendingToolSelection: first.expectsToolSelection,
      );
      expect(answer.tool?.id, 'xiaoliuren');

      final ambiguous = AssistantConversationOrchestrator.resolve(
        query: '易经和梅花易数',
        selectedMode: AssistantMode.automatic,
        currentMode: first.mode,
        pendingToolSelection: first.expectsToolSelection,
      );
      expect(ambiguous.needsClarification, isTrue);
      expect(ambiguous.clarification, contains('只选择其中一个'));
    });

    test('工具手动模式中的澄清答案不要求重复动作词', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '经方剂量换算',
        selectedMode: AssistantMode.tools,
        currentMode: AssistantMode.tools,
        pendingToolSelection: true,
      );
      expect(decision.tool?.id, 'dosage');
    });


    test('只有存在待选工具澄清状态时，短工具别名才允许启动页面', () {
      final ordinaryMention = AssistantConversationOrchestrator.resolve(
        query: '紫微斗数',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
      );
      expect(ordinaryMention.tool, isNull);
      expect(ordinaryMention.expectsToolSelection, isFalse);

      final pendingChoice = AssistantConversationOrchestrator.resolve(
        query: '紫微斗数',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
        pendingToolSelection: true,
      );
      expect(pendingChoice.tool?.id, 'ziwei');
    });

    test('待选工具期间询问历史背景应切换为学习助手', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '紫微斗数的历史背景',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
        pendingToolSelection: true,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.tool, isNull);
      expect(decision.expectsToolSelection, isFalse);
    });

    test('待选工具状态可被明确取消，或由本人症状请求接管', () {
      final cancelled = AssistantConversationOrchestrator.resolve(
        query: '算了，先不排了',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
        pendingToolSelection: true,
      );
      expect(cancelled.expectsToolSelection, isFalse);
      expect(cancelled.tool, isNull);

      final symptom = AssistantConversationOrchestrator.resolve(
        query: '我最近头痛',
        selectedMode: AssistantMode.automatic,
        currentMode: AssistantMode.metaphysics,
        pendingToolSelection: true,
      );
      expect(symptom.mode, AssistantMode.consultation);
      expect(symptom.expectsToolSelection, isFalse);
    });

    test('日期参数保留原始输入，由执行边界拒绝无效日历日期', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我推算五运六气 2026-02-30',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.tool?.id, 'yunqi');
      expect(decision.toolArguments?.values, const {'date': '2026-02-30'});
      expect(
        decision.toolArguments!.validateAgainst(decision.tool!),
        isNotEmpty,
      );
    });

    test('手动玄学模式的泛化排盘请求也会先澄清', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我排个盘',
        selectedMode: AssistantMode.metaphysics,
      );
      expect(decision.needsClarification, isTrue);
      expect(decision.expectsToolSelection, isTrue);
    });

    test('统一助手工具注册表覆盖 ToolsScreen 的全部可调用业务页面', () {
      final ids = AssistantToolRouter.all.map((tool) => tool.id).toSet();
      expect(ids.length, AssistantToolRouter.all.length);
      expect(ids, containsAll(<String>[
        'structured_diagnosis', 'yunqi', 'ziwei', 'bazi', 'yijing',
        'xiaoliuren', 'meihua', 'dosage', 'ziwu_liuzhu', 'guji_library',
        'medical_cases', 'almanac', 'diagnosis_history', 'critical_illness',
        'solar_terms', 'yuxiaji_omen', 'dream', 'guansha',
        'sanshan_lingqian', 'chenggu', 'shousheng_debt', 'huangdi_siji',
        'saved_charts',
      ]));
    });

    test('玄学工具路由保持民俗工具边界，不混入医学问诊', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我测算小儿关煞',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.metaphysics);
      expect(decision.tool?.id, 'guansha');
    });

    test('工具角色能路由到此前未接入 AI 的实用工具', () {
      final cases = <({String query, String id})>[
        (query: '打开诊断历史趋势', id: 'diagnosis_history'),
        (query: '查阅闭门课重症临床', id: 'critical_illness'),
        (query: '打开节气养生', id: 'solar_terms'),
        (query: '查询玉匣灵兆', id: 'yuxiaji_omen'),
        (query: '搜索周公解梦', id: 'dream'),
        (query: '测算小儿关煞', id: 'guansha'),
        (query: '帮我抽三山灵签', id: 'sanshan_lingqian'),
        (query: '计算袁天罡称骨', id: 'chenggu'),
        (query: '查询受生债', id: 'shousheng_debt'),
        (query: '查看黄帝四季歌', id: 'huangdi_siji'),
        (query: '打开我的命盘库', id: 'saved_charts'),
      ];
      for (final item in cases) {
        final decision = AssistantConversationOrchestrator.resolve(
          query: item.query,
          selectedMode: AssistantMode.automatic,
        );
        expect(decision.tool?.id, item.id, reason: item.query);
      }
    });

    test('同一请求明确调用两个工具时必须澄清，不得静默只执行第一个', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我推算五运六气，再帮我排八字',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.tool, isNull);
      expect(decision.needsClarification, isTrue);
      expect(decision.expectsToolSelection, isTrue);
      expect(decision.clarification, contains('五运六气'));
      expect(decision.clarification, contains('八字'));
    });

    test('手动工具模式下同时指定多个工具也必须先澄清', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '推算五运六气并计算经方剂量换算',
        selectedMode: AssistantMode.tools,
      );
      expect(decision.tool, isNull);
      expect(decision.needsClarification, isTrue);
      expect(decision.expectsToolSelection, isTrue);
    });

    test('学习语境优先于症状关键词', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '学习口苦在少阳病中的含义',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.learning);
      expect(decision.needsClarification, isFalse);
    });
  });
}
