import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Native transcript restore hydrates typed turns without model generation', () async {
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
    expect(resetMethod, contains('conversationHistory.restore(restoredHistory)'));
    expect(resetMethod, contains('createConversationWithHistory(engine)'));
    expect(resetMethod, contains('if (restoredHistory == null)'));
  });
}
