import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/assistant_conversation_orchestrator.dart';

void main() {
  group('统一助手自动调度', () {
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
