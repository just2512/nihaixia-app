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
      expect(result.completedTurns, [
        const LocalAiTranscriptTurn(userText: '第一问', assistantText: '第一答'),
        const LocalAiTranscriptTurn(userText: '第二问', assistantText: '第二答'),
      ]);
      expect(result.omittedCompletedTurnCount, 0);
      expect(result.omittedCompletedCharacterCount, 0);
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
      expect(result.completedTurns, hasLength(12));
      expect(result.completedTurns.first.userText, startsWith('USER_TURN_108'));
      expect(result.completedTurns.last.userText, startsWith('USER_TURN_119'));
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
          text: List.filled(LocalAiTranscriptRestorePolicy.maxTranscriptCharacters, 'U').join(),
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
      expect(result.omittedCompletedTurnCount, 1);
      expect(result.completedTurns, isEmpty);
      expect(result.omittedCompletedCharacterCount,
          LocalAiTranscriptRestorePolicy.maxTranscriptCharacters +
              'complete response'.length);
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
      expect(result.omittedCompletedTurnCount, 0);
      expect(result.completedTurns, hasLength(1));
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
    test('projects only the latest sixty user messages and preserves truncation', () {
      final projection = LocalAiTranscriptRestorePolicy.projectUserMessages(
        (1..75).map((index) => 'user-$index'),
      );

      expect(projection.messages, hasLength(60));
      expect(projection.messages.first, 'user-16');
      expect(projection.messages.last, 'user-75');
      expect(projection.truncated, isTrue);
    });

    test('bounds each formatted user entry without splitting a surrogate pair', () {
      final prefix = List<String>.filled(
        LocalAiTranscriptRestorePolicy.maxUserMessageCharacters - 1,
        'a',
      ).join();
      final raw = '${prefix}😀z';
      final projection = LocalAiTranscriptRestorePolicy.projectUserMessages([raw]);

      expect(projection.truncated, isTrue);
      expect(projection.messages, hasLength(1));
      expect(
        projection.messages.single.length,
        LocalAiTranscriptRestorePolicy.maxUserMessageCharacters - 1,
      );
      expect(projection.messages.single, endsWith('a'));
      final lastCodeUnit = projection.messages.single.codeUnitAt(
        projection.messages.single.length - 1,
      );
      expect(lastCodeUnit, lessThan(0xD800));
    });

    test('bounds formatted aggregate characters while retaining newest entries', () {
      final body = List<String>.filled(
        LocalAiTranscriptRestorePolicy.maxUserMessageCharacters - 8,
        'x',
      ).join();
      final rawMessages = [
        for (var index = 0; index < 9; index++) 'entry-$index $body',
      ];
      final projection =
          LocalAiTranscriptRestorePolicy.projectUserMessages(rawMessages);

      expect(projection.truncated, isTrue);
      expect(projection.messages, hasLength(8));
      expect(projection.messages.first, startsWith('entry-1 '));
      expect(projection.messages.last, startsWith('entry-8 '));
      final formattedCharacters = projection.messages.fold<int>(
        0,
        (sum, message) => sum + message.length +
            LocalAiTranscriptRestorePolicy.userMessageSourcePrefix.length,
      );
      expect(
        formattedCharacters,
        lessThanOrEqualTo(
          LocalAiTranscriptRestorePolicy.maxTotalUserMessageCharacters,
        ),
      );
    });

    test('does not mark an empty or short user projection as truncated', () {
      final empty = LocalAiTranscriptRestorePolicy.projectUserMessages(
        const <String>[' ', '\n'],
      );
      final short = LocalAiTranscriptRestorePolicy.projectUserMessages(
        const <String>['第一条自述', '第二条自述'],
      );

      expect(empty.messages, isEmpty);
      expect(empty.truncated, isFalse);
      expect(short.messages, ['第一条自述', '第二条自述']);
      expect(short.truncated, isFalse);
    });
  });
}
