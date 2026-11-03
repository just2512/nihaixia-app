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

    test('明确工具动作自动路由五运六气', () {
      final decision = AssistantConversationOrchestrator.resolve(
        query: '帮我推算五运六气',
        selectedMode: AssistantMode.automatic,
      );
      expect(decision.mode, AssistantMode.tools);
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
