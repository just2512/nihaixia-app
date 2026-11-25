import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_transcript_restore_policy.dart';

void main() {
  group('LocalAiTranscriptRestorePolicy', () {
    test('preserves short complete turns and the leading assistant prelude', () {
      final result = LocalAiTranscriptRestorePolicy.fromMessages([
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.assistant,
          text: '欢迎使用助手',
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.user,
          text: '第一问',
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.assistant,
          text: '第一答',
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.user,
          text: '第二问',
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.assistant,
          text: '第二答',
        ),
      ]);

      expect(
        result.transcript,
        '助手：欢迎使用助手\n用户：第一问\n助手：第一答\n'
        '用户：第二问\n助手：第二答',
      );
      expect(result.retainedTurnCount, 2);
      expect(result.omittedTurnCount, 0);
      expect(result.omittedCharacterCount, 0);
    });

    test('omits oldest complete turns and never cuts the newest turn', () {
      final messages = <LocalAiTranscriptMessage>[];
      for (var index = 0; index < 120; index++) {
        messages
          ..add(LocalAiTranscriptMessage(
            role: LocalAiTranscriptRole.user,
            text: 'USER_TURN_$index ${List.filled(40, '旧内容').join()}',
          ))
          ..add(LocalAiTranscriptMessage(
            role: LocalAiTranscriptRole.assistant,
            text: 'ASSISTANT_TURN_$index ${List.filled(40, '答复').join()}',
          ));
      }

      final result = LocalAiTranscriptRestorePolicy.fromMessages(messages);

      expect(result.transcript, startsWith(
        LocalAiTranscriptRestorePolicy.truncationMarker,
      ));
      expect(result.transcript, contains('USER_TURN_119'));
      expect(result.transcript, contains('ASSISTANT_TURN_119'));
      expect(result.transcript, isNot(contains('USER_TURN_0')));
      expect(result.transcript.length,
          lessThanOrEqualTo(LocalAiTranscriptRestorePolicy.maxTranscriptCharacters));
      expect(result.omittedTurnCount, greaterThan(0));
      expect(result.retainedTurnCount, greaterThan(0));
    });

    test('omits a single oversized turn whole rather than replaying a suffix', () {
      final result = LocalAiTranscriptRestorePolicy.fromMessages([
        LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.user,
          text: 'U' * LocalAiTranscriptRestorePolicy.maxTranscriptCharacters,
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.assistant,
          text: 'complete response',
        ),
      ]);

      expect(
        result.transcript,
        LocalAiTranscriptRestorePolicy.truncationMarker,
      );
      expect(result.retainedTurnCount, 0);
      expect(result.omittedTurnCount, 1);
      expect(result.transcript.length,
          lessThanOrEqualTo(LocalAiTranscriptRestorePolicy.maxTranscriptCharacters));
    });

    test('does not replay an unfinished user turn', () {
      final result = LocalAiTranscriptRestorePolicy.fromMessages([
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.user,
          text: '已完成的问题',
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.assistant,
          text: '已完成的回答',
        ),
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.user,
          text: '尚未完成的问题',
        ),
      ]);

      expect(result.transcript, contains('已完成的问题'));
      expect(result.transcript, isNot(contains('尚未完成的问题')));
      expect(result.omittedTurnCount, 1);
    });

    test('counts UTF-16 code units without splitting surrogate pairs', () {
      final messages = <LocalAiTranscriptMessage>[
        for (var index = 0; index < 100; index++) ...[
          LocalAiTranscriptMessage(
            role: LocalAiTranscriptRole.user,
            text: '问题😀$index ${List.filled(80, '用户').join()}',
          ),
          LocalAiTranscriptMessage(
            role: LocalAiTranscriptRole.assistant,
            text: '回答😀$index ${List.filled(80, '回复').join()}',
          ),
        ],
      ];

      final result = LocalAiTranscriptRestorePolicy.fromMessages(messages);

      expect(result.transcript.length,
          lessThanOrEqualTo(LocalAiTranscriptRestorePolicy.maxTranscriptCharacters));
      expect(result.transcript, endsWith('回答😀99 ${List.filled(80, '回复').join()}'));
    });

    test('keeps assistant-only prelude when there is no user turn', () {
      final result = LocalAiTranscriptRestorePolicy.fromMessages([
        const LocalAiTranscriptMessage(
          role: LocalAiTranscriptRole.assistant,
          text: '欢迎使用助手',
        ),
      ]);

      expect(result.transcript, '助手：欢迎使用助手');
      expect(result.omittedTurnCount, 0);
      expect(result.retainedTurnCount, 1);
    });
  });
}
