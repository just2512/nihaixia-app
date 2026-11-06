import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/tcm_interview_conversation_controller.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';

void main() {
  group('统一对话中的结构化问诊控制器', () {
    test('启动时把用户请求、上下文和首个规则问题保留在同一 transcript', () {
      final controller = TcmInterviewConversationController();
      controller.start(
        initialUserMessage: '开始规则辨证',
        userContext: '最近头痛，睡眠后缓解',
      );

      expect(controller.pendingPromptId, 'temperature');
      expect(controller.pendingPromptText, contains('寒热感觉'));
      expect(controller.pendingOptions, isNotEmpty);
      expect(
        controller.messages.map((message) => message.text),
        containsAll([
          '开始规则辨证',
          contains('最近头痛，睡眠后缓解'),
        ]),
      );
      expect(controller.messages.last.text, controller.pendingPromptText);
    });

    test('只能提交当前问题提供的选项，回答后推进到下一条问诊', () {
      final controller = TcmInterviewConversationController();
      controller.start();
      final firstOption = controller.pendingOptions.first;

      expect(
        () => controller.answerOption('并非当前选项'),
        throwsArgumentError,
      );
      expect(controller.pendingPromptId, 'temperature');

      controller.answerOption(firstOption);
      expect(controller.pendingPromptId, 'tongue_pulse');
      expect(controller.pendingOptions, contains('跳过，直接问诊'));

      controller.answerOption('跳过，直接问诊');
      expect(controller.pendingPromptId, startsWith('ten:'));
      expect(controller.pendingOptions, isNotEmpty);
    });

    test('主脉和兼脉通过同一问诊任务提交并持久化', () {
      final controller = TcmInterviewConversationController();
      controller.start();
      controller.answerOption(controller.pendingOptions.first);

      controller.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        primaryPulse: '浮',
        secondaryPulse: '紧',
      );

      final state = controller.createTaskState();
      expect(state.snapshot.tongueCoating, '薄白');
      expect(state.snapshot.tongueShape, '淡白');
      expect(state.snapshot.pulseType, '浮');
      expect(state.snapshot.pulseTypeSecondary, '紧');
      expect(state.status, 'in_progress');
      expect(state.pendingPromptId, startsWith('ten:'));
    });

    test('未完成任务恢复后保留原问题、选项和引擎快照', () {
      final controller = TcmInterviewConversationController();
      controller.start();
      controller.answerOption(controller.pendingOptions.first);
      controller.answerOption('跳过，直接问诊');

      final saved = TcmInterviewTaskState.decode(
        controller.createTaskState().encode(),
      );
      final restored = TcmInterviewConversationController.restore(saved);

      expect(restored.pendingPromptId, saved.pendingPromptId);
      expect(restored.pendingPromptText, saved.pendingPromptText);
      expect(restored.pendingOptions, saved.pendingOptions);
      expect(
        restored.messages.map((message) => message.text),
        saved.transcript.map((message) => message.text),
      );

      restored.answerOption(restored.pendingOptions.first);
      expect(restored.messages.length, greaterThan(saved.transcript.length));
      expect(restored.pendingPromptId, isNot(saved.pendingPromptId));
    });
  });
}
