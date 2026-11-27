import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Native transcript restore hydrates typed turns without model generation or an empty intermediate conversation',
    () async {
      final source = await File(
        'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
      ).readAsString();
      final start = source.indexOf('private fun restoreLocalConversation(');
      final end = source.indexOf('private fun resetLocalConversation(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));

      final restore = source.substring(start, end);
      final validation = restore.indexOf(
        'LocalAiTranscriptRestorePolicy.historySnapshot',
      );
      final reset = restore.indexOf(
        'resetLocalConversation(conversationId, restoredSnapshot)',
      );
      expect(validation, greaterThanOrEqualTo(0));
      expect(reset, greaterThan(validation));
      expect(restore, isNot(contains('conversationHistory.restore(')));
      expect(restore, isNot(contains('recreateCurrentConversationFromHistory()')));
      expect(restore, isNot(contains('sendWithFirstTurnGpuFallback')));
      expect(restore, isNot(contains('conversation.sendMessage(')));

      final resetStart = source.indexOf('private fun resetLocalConversation(');
      final resetEnd = source.indexOf('private fun releaseLocalModel(', resetStart);
      expect(resetStart, greaterThanOrEqualTo(0));
      expect(resetEnd, greaterThan(resetStart));
      final resetMethod = source.substring(resetStart, resetEnd);
      expect(
        resetMethod,
        contains('restoredHistory: LocalAiConversationHistorySnapshot? = null'),
      );
      final restoreHistory = resetMethod.indexOf(
        'conversationHistory.restore(restoredHistory)',
      );
      final createWithHistory = resetMethod.indexOf(
        'createConversationWithHistory(engine)',
      );
      expect(restoreHistory, greaterThanOrEqualTo(0));
      expect(createWithHistory, greaterThan(restoreHistory));
      expect(
        'createConversationWithHistory(engine)'.allMatches(resetMethod),
        hasLength(1),
      );
      expect(resetMethod, contains('if (restoredHistory == null)'));
    },
  );

  test(
    'Native restore rejects incomplete MethodChannel payload before queueing work',
    () async {
      final source = await File(
        'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
      ).readAsString();
      final start = source.indexOf('"restoreConversation" -> {');
      final end = source.indexOf('"resetConversation" -> {', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));

      final handler = source.substring(start, end);
      final validation = handler.indexOf(
        'LocalAiTranscriptRestorePolicy.parsePayload',
      );
      final queue = handler.indexOf(
        'runAiTask(result, requiresAiAccess = true)',
      );
      expect(validation, greaterThanOrEqualTo(0));
      expect(queue, greaterThan(validation));
      expect(handler, contains('INVALID_RESTORE_PAYLOAD'));
      expect(handler, contains('return@handler'));
      expect(handler, isNot(contains('?: emptyList')));
      expect(handler, isNot(contains('?: 0')));
    },
  );
}
