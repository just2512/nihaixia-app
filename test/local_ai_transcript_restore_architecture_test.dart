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
    expect(restore, contains('LocalAiTranscriptRestorePolicy.historySnapshot'));
    expect(restore, contains('conversationHistory.restore(restoredSnapshot)'));
    expect(restore, contains('recreateCurrentConversationFromHistory()'));
    expect(restore, isNot(contains('sendWithFirstTurnGpuFallback')));
    expect(restore, isNot(contains('conversation.sendMessage(')));
  });
}
