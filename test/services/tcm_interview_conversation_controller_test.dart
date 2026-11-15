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
      final transcript = controller.messages.map((message) => message.text);
      expect(transcript, contains('开始规则辨证'));
      expect(
        transcript.any((text) => text.contains('最近头痛，睡眠后缓解')),
        isTrue,
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

    test('只将用户确认的十问候选按原题序写入规则引擎，其余问题继续追问', () {
      final controller = TcmInterviewConversationController();
      final firstQuestion = controller.symptomQuestionSchema.first;
      final questionId = firstQuestion['id']! as String;
      final answer = (firstQuestion['options']! as List).first as String;

      controller.start(
        initialUserMessage: '最近有睡眠问题',
        userContext: '最近有睡眠问题',
        confirmedTenAnswers: {questionId: answer},
      );
      expect(controller.pendingPromptId, 'temperature');

      controller.answerOption(controller.pendingOptions.first);
      controller.answerOption('跳过，直接问诊');

      final state = controller.createTaskState();
      expect(state.snapshot.answers[questionId], answer);
      expect(controller.pendingPromptId, startsWith('ten:'));
      expect(controller.pendingPromptId, isNot('ten:' + questionId));
      expect(
        controller.messages.any((message) =>
            message.text.contains('已确认自述对应问项') &&
            message.text.contains(answer)),
        isTrue,
      );
    });

    test('未消费的已确认候选在任务恢复后仍保留，不改变当前待问项目', () {
      final controller = TcmInterviewConversationController();
      final schema = controller.symptomQuestionSchema;
      final lastQuestion = schema.last;
      final questionId = lastQuestion['id']! as String;
      final answer = (lastQuestion['options']! as List).first as String;

      controller.start(confirmedTenAnswers: {questionId: answer});
      controller.answerOption(controller.pendingOptions.first);
      controller.answerOption('跳过，直接问诊');

      final saved = TcmInterviewTaskState.decode(
        controller.createTaskState().encode(),
      );
      expect(saved.pendingConfirmedTenAnswers, {questionId: answer});
      final restored = TcmInterviewConversationController.restore(saved);
      expect(
        restored.createTaskState().pendingConfirmedTenAnswers,
        {questionId: answer},
      );
      expect(restored.pendingPromptId, saved.pendingPromptId);
      expect(restored.pendingOptions, saved.pendingOptions);
    });

    test('自然语言澄清只更新当前问项提示，不写入规则引擎答案', () {
      final controller = TcmInterviewConversationController();
      controller.start();
      controller.answerOption(controller.pendingOptions.first);
      controller.answerOption('跳过，直接问诊');
      final before = controller.createTaskState().snapshot.answers;

      expect(controller.canAcceptNaturalLanguageAnswer, isTrue);
      controller.recordNaturalLanguageInput('晚上睡觉时醒了两次');
      controller.updatePendingPrompt('你醒来后还能再次入睡吗？');

      final pending = controller.createTaskState();
      expect(pending.pendingPromptId, startsWith('ten:'));
      expect(pending.pendingPromptText, '你醒来后还能再次入睡吗？');
      expect(pending.pendingOptions, isNotEmpty);
      expect(pending.snapshot.answers, before,
          reason: '自然语言理解与澄清不能直接写入 DiagnosticEngine');
      expect(pending.transcript.last.hasPendingOptions, isTrue);
      expect(
        TcmInterviewTaskState.decode(pending.encode()).transcript.last.hasPendingOptions,
        isTrue,
      );
      final restored = TcmInterviewConversationController.restore(
        TcmInterviewTaskState.decode(pending.encode()),
      );
      expect(restored.pendingPromptText, '你醒来后还能再次入睡吗？');
      expect(restored.pendingPromptId, pending.pendingPromptId);
      expect(restored.pendingOptions, pending.pendingOptions);
    });

    test('舌脉选择器和寒热真假多选步骤不接受单选自然语言映射', () {
      final controller = TcmInterviewConversationController();
      controller.start();
      controller.answerOption(controller.pendingOptions.first);
      expect(controller.pendingPromptId, 'tongue_pulse');
      expect(controller.canAcceptNaturalLanguageAnswer, isFalse);
      controller.answerOption('跳过，直接问诊');
      controller.answerOption(controller.pendingOptions.first);
      controller.answerOption('跳过舌诊脉诊');
      expect(controller.canAcceptNaturalLanguageAnswer, isFalse);
    });

    test('拒绝非当前十问题目或选项的模型候选', () {
      final controller = TcmInterviewConversationController();
      expect(
        () => controller.start(
          confirmedTenAnswers: const {'not_a_question': '任意答案'},
        ),
        throwsArgumentError,
      );
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
