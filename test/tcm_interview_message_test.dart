import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/tcm_interview_message.dart';

void main() {
  group('TcmInterviewMessage', () {
    test('round trips a structured question and its canonical options', () {
      final timestamp = DateTime.utc(2026, 11, 5, 1, 0);
      final original = TcmInterviewMessage(
        id: 'task-1:question:temperature',
        taskId: 'task-1',
        type: TcmInterviewMessageType.question,
        content: '你整体的寒热感觉是怎样的？',
        createdAt: timestamp,
        promptId: 'temperature_pattern',
        options: const ['怕冷', '怕热', '寒热错杂'],
        source: 'diagnostic.temperature',
      );

      final restored = TcmInterviewMessage.decode(original.encode());
      expect(restored.id, original.id);
      expect(restored.taskId, original.taskId);
      expect(restored.type, TcmInterviewMessageType.question);
      expect(restored.promptId, original.promptId);
      expect(restored.options, original.options);
      expect(restored.createdAt, timestamp);
    });

    test('round trips an answer without losing its selected option', () {
      final message = TcmInterviewMessage(
        id: 'task-1:answer:temperature',
        taskId: 'task-1',
        type: TcmInterviewMessageType.answer,
        content: '怕冷',
        createdAt: DateTime.utc(2026, 11, 5),
        promptId: 'temperature_pattern',
        selectedAnswer: '怕冷',
      );

      final restored = TcmInterviewMessage.decode(message.encode());
      expect(restored.selectedAnswer, '怕冷');
      expect(restored.promptId, 'temperature_pattern');
    });

    test('rejects unknown schema versions and message types', () {
      expect(
        () => TcmInterviewMessage.fromJson({
          'schemaVersion': 2,
          'id': 'm1',
          'taskId': 't1',
          'type': 'question',
          'content': 'Q',
          'createdAt': '2026-11-05T00:00:00Z',
          'options': [],
        }),
        throwsFormatException,
      );
      expect(
        () => TcmInterviewMessage.fromJson({
          'schemaVersion': 1,
          'id': 'm1',
          'taskId': 't1',
          'type': 'unknown',
          'content': 'Q',
          'createdAt': '2026-11-05T00:00:00Z',
          'options': [],
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed options and missing task identity', () {
      expect(
        () => TcmInterviewMessage.fromJson({
          'schemaVersion': 1,
          'id': 'm1',
          'taskId': '',
          'type': 'question',
          'content': 'Q',
          'createdAt': '2026-11-05T00:00:00Z',
          'options': ['valid', 3],
        }),
        throwsFormatException,
      );
    });
  });
}
