import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/headless_tool_result_handler.dart';

void main() {
  group('HeadlessToolResultHandler', () {
    test('normalizes a successful page result and keeps persistence outside the handler', () {
      const arguments = {'date': '2026-11-23'};
      final result = AssistantToolResult(
        toolId: 'yunqi',
        title: '五运六气推算',
        values: const {'结果': '页面返回的本地计算结果'},
        arguments: arguments,
        sourceIds: const ['local-engine:yunqi'],
      );

      final presentation = HeadlessToolResultHandler.handlePage(
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        rawResult: result,
        expectedArguments: arguments,
        aiReady: true,
      );

      expect(presentation.resultContractErrors, isEmpty);
      expect(presentation.argumentErrors, isEmpty);
      expect(presentation.responseText, contains('页面返回的本地计算结果'));
      expect(presentation.responseText, contains('执行结果】\n'));
      expect(presentation.canInterpret, isTrue);
      expect(presentation.autoInterpret, isTrue);
      expect(presentation.canRetry, isFalse);
      expect(presentation.result.arguments, arguments);
    });

    test('keeps legacy page text visible but not eligible for AI interpretation', () {
      final presentation = HeadlessToolResultHandler.handlePage(
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        rawResult: '旧页面返回的文本',
        expectedArguments: const {'date': '2026-11-23'},
        aiReady: true,
      );

      expect(presentation.resultContractErrors, isEmpty);
      expect(presentation.responseText, contains('旧页面返回的文本'));
      expect(presentation.result.status, AssistantToolExecutionStatus.unknown);
      expect(presentation.canInterpret, isFalse);
      expect(presentation.autoInterpret, isFalse);
    });

    test('represents a page exit without a result as no-result, not success', () {
      final presentation = HeadlessToolResultHandler.handlePage(
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        rawResult: null,
        expectedArguments: const {'date': '2026-11-23'},
        aiReady: true,
      );

      expect(presentation.result.status, AssistantToolExecutionStatus.unknown);
      expect(presentation.responseText, contains('MISSING'));
      expect(presentation.responseText, contains('执行结果】\n'));
      expect(presentation.canInterpret, isFalse);
      expect(presentation.autoInterpret, isFalse);
    });

    test('rejects mismatched result identity and arguments before presentation', () {
      final result = AssistantToolResult(
        toolId: 'bazi',
        title: '八字排盘',
        values: const {'结果': '不应展示'},
        arguments: const {'birth_date': '1990-01-01'},
        sourceIds: const ['local-engine:bazi'],
      );

      final presentation = HeadlessToolResultHandler.handle(
        userText: '帮我排盘',
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        expectedArguments: const {'date': '2026-11-23'},
        result: result,
        aiReady: true,
      );

      expect(presentation.contractErrors, isNotEmpty);
      expect(presentation.responseText, isEmpty);
      expect(presentation.canInterpret, isFalse);
      expect(presentation.autoInterpret, isFalse);
    });

    test('builds a validated result presentation without auto-interpreting when AI is unavailable', () {
      const arguments = {'date': '2026-11-23'};
      final result = AssistantToolResult(
        toolId: 'yunqi',
        title: '五运六气推算',
        values: const {'结果': '已由 App 本地引擎计算'},
        arguments: arguments,
        sourceIds: const ['local-engine:yunqi'],
      );

      final presentation = HeadlessToolResultHandler.handle(
        userText: '推算今天的五运六气',
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        expectedArguments: arguments,
        result: result,
        aiReady: false,
      );

      expect(presentation.contractErrors, isEmpty);
      expect(presentation.responseText, contains('五运六气推算执行结果'));
      expect(presentation.responseText, contains('执行结果】\n'));
      expect(presentation.responseText, contains('已由 App 本地引擎计算'));
      expect(presentation.canInterpret, isTrue);
      expect(presentation.autoInterpret, isFalse);
      expect(presentation.toolStatusForPersistence, result.statusLabel);
      expect(presentation.argumentsForPersistence, arguments);
      expect(presentation.sourceIds, result.sourceIds);
    });

    test('allows automatic interpretation only when the model is ready', () {
      const arguments = {'date': '2026-11-23'};
      final result = AssistantToolResult(
        toolId: 'yunqi',
        title: '五运六气推算',
        values: const {'结果': '已计算'},
        arguments: arguments,
        sourceIds: const ['local-engine:yunqi'],
      );

      final presentation = HeadlessToolResultHandler.handle(
        userText: '解释一下',
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        expectedArguments: arguments,
        result: result,
        aiReady: true,
      );

      expect(presentation.canInterpret, isTrue);
      expect(presentation.autoInterpret, isTrue);
      expect(presentation.interpretationPrompt, contains('确定性计算/数据'));
    });

    test('presents UNKNOWN executor outcomes without AI interpretation', () {
      const arguments = {'date': '2026-11-23'};
      const result = AssistantToolResult(
        toolId: 'yunqi',
        title: 'untrusted-executor-title',
        status: AssistantToolExecutionStatus.unknown,
        values: {'执行状态': 'UNKNOWN'},
        arguments: arguments,
        disclaimer: '执行器未返回可验证结果，不会自动重放。',
      );

      final presentation = HeadlessToolResultHandler.handle(
        userText: '推算今天的五运六气',
        toolId: 'yunqi',
        toolTitle: '五运六气推算',
        expectedArguments: arguments,
        result: result,
        aiReady: true,
      );

      expect(presentation.contractErrors, isEmpty);
      expect(presentation.responseText, contains('工具：五运六气推算'));
      expect(presentation.responseText, isNot(contains('untrusted-executor-title')));
      expect(presentation.responseText, contains('UNKNOWN'));
      expect(presentation.canInterpret, isFalse);
      expect(presentation.autoInterpret, isFalse);
      expect(presentation.toolStatusForPersistence, 'UNKNOWN');
    });

    test('returns a dream clarification intent without claiming a completed match', () {
      const arguments = {'dream': '梦见河水'};
      final result = AssistantToolResult(
        toolId: 'dream',
        title: '梦境民俗检索',
        status: AssistantToolExecutionStatus.noResult,
        values: const {
          '检索状态': 'CANDIDATES_REQUIRE_CLARIFICATION',
          '候选': '河水；洪水',
        },
        arguments: arguments,
        sourceIds: const ['local-knowledge:dream'],
      );

      final presentation = HeadlessToolResultHandler.handle(
        userText: '我梦见河水',
        toolId: 'dream',
        toolTitle: '梦境民俗检索',
        expectedArguments: arguments,
        result: result,
        aiReady: true,
      );

      expect(presentation.needsDreamFollowUp, isTrue);
      expect(presentation.needsBirthplaceFollowUp, isFalse);
      expect(
        presentation.followUp?.kind,
        HeadlessToolFollowUpKind.dreamClarification,
      );
      expect(presentation.toolStatusForPersistence, 'AWAITING_PARAMETERS');
      expect(presentation.canInterpret, isFalse);
      expect(presentation.interpretationPrompt, contains('只向用户追问一个'));
    });

    test('returns a structured birthplace clarification intent and retains the original arguments', () {
      const arguments = {
        'birth_date': '1990-01-01',
        'birth_time': '12:00',
        'birthplace': '未知城市',
      };
      final result = AssistantToolResult(
        toolId: 'bazi',
        title: '八字排盘',
        status: AssistantToolExecutionStatus.failed,
        values: const {'未执行原因': '无法唯一识别出生地点'},
        arguments: arguments,
      );

      final presentation = HeadlessToolResultHandler.handle(
        userText: '帮我排八字',
        toolId: 'bazi',
        toolTitle: '八字排盘',
        expectedArguments: arguments,
        result: result,
        aiReady: true,
      );

      expect(presentation.needsBirthplaceFollowUp, isTrue);
      expect(
        presentation.followUp?.kind,
        HeadlessToolFollowUpKind.birthplaceClarification,
      );
      expect(presentation.responseText, contains('补充省/州和城市/区县'));
      expect(presentation.toolStatusForPersistence, 'AWAITING_PARAMETERS');
      expect(presentation.argumentsForPersistence, arguments);
      expect(presentation.canInterpret, isFalse);
    });
  });
}
