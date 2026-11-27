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
    final reset = restore.indexOf('resetLocalConversation(conversationId)');
    expect(validation, greaterThanOrEqualTo(0));
    expect(reset, greaterThan(validation));
    expect(restore, contains('conversationHistory.restore(restoredSnapshot)'));
    expect(restore, contains('recreateCurrentConversationFromHistory()'));
    expect(restore, isNot(contains('sendWithFirstTurnGpuFallback')));
    expect(restore, isNot(contains('conversation.sendMessage(')));
  });
  test('Native restore rejects incomplete MethodChannel payload before queueing work', () async {
    final source = await File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
    ).readAsString();
    final start = source.indexOf('"restoreConversation" -> {');
    final end = source.indexOf('"resetConversation" -> {', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    final validation = handler.indexOf('LocalAiTranscriptRestorePolicy.parsePayload');
    final queue = handler.indexOf('runAiTask(result, requiresAiAccess = true)');
    expect(validation, greaterThanOrEqualTo(0));
    expect(queue, greaterThan(validation));
    expect(handler, contains('INVALID_RESTORE_PAYLOAD'));
    expect(handler, contains('return@handler'));
    expect(handler, isNot(contains('?: emptyList')));
    expect(handler, isNot(contains('?: 0')));
  });

}
