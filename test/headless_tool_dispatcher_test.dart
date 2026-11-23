import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/headless_tool_dispatcher.dart';

void main() {
  group('HeadlessToolDispatcher', () {
    const arguments = <String, String>{
      'date': '2026-11-23',
    };

    final expected = AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: const {'结果': '测试结果'},
      arguments: arguments,
      sourceIds: const ['local-engine:yunqi'],
    );

    test('invokes the registered executor once with the original argument map', () async {
      var calls = 0;
      Map<String, String>? receivedArguments;

      final actual = await HeadlessToolDispatcher.execute(
        tool: AssistantToolRouter.yunqi,
        arguments: arguments,
        executorOverride: (received) {
          calls += 1;
          receivedArguments = received;
          return expected;
        },
      );

      expect(calls, 1);
      expect(identical(receivedArguments, arguments), isTrue);
      expect(identical(actual, expected), isTrue);
    });

    test('awaits an asynchronous executor and returns its typed result unchanged', () async {
      var completed = false;
      final actual = await HeadlessToolDispatcher.execute(
        tool: AssistantToolRouter.yunqi,
        arguments: arguments,
        executorOverride: (received) async {
          await Future<void>.delayed(Duration.zero);
          completed = true;
          expect(received, arguments);
          return expected;
        },
      );

      expect(completed, isTrue);
      expect(identical(actual, expected), isTrue);
    });

    test('uses the test override for a Page-only definition without changing production metadata', () async {
      final pageOnly = AssistantToolRouter.byId('guji_library')!;
      expect(pageOnly.headlessExecutor, isNull);

      final actual = await HeadlessToolDispatcher.execute(
        tool: pageOnly,
        arguments: const {},
        executorOverride: (_) => AssistantToolResult(
          toolId: pageOnly.id,
          title: pageOnly.title,
          values: const {'状态': '测试'},
        ),
      );

      expect(actual.toolId, pageOnly.id);
      expect(pageOnly.headlessExecutor, isNull);
    });

    test('rejects a Page-only tool when no executor is registered', () async {
      final pageOnly = AssistantToolRouter.byId('guji_library')!;
      await expectLater(
        HeadlessToolDispatcher.execute(
          tool: pageOnly,
          arguments: const {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('propagates the executor error without converting it to a business result', () async {
      final error = StateError('executor failure');
      await expectLater(
        HeadlessToolDispatcher.execute(
          tool: AssistantToolRouter.yunqi,
          arguments: arguments,
          executorOverride: (_) => throw error,
        ),
        throwsA(same(error)),
      );
    });
  });
}
