/// Bounds the transcript replayed when a persisted assistant conversation
/// is restored into the Native LiteRT-LM conversation.
///
/// The budget is measured in Dart UTF-16 code units, matching Kotlin String.
/// Only complete user/assistant turns are retained; a message is never cut
/// mid-sentence, and an incomplete final turn is never replayed as complete.
enum LocalAiTranscriptRole { user, assistant }

class LocalAiTranscriptMessage {
  const LocalAiTranscriptMessage({required this.role, required this.text});
  final LocalAiTranscriptRole role;
  final String text;
}

class LocalAiTranscriptTurn {
  const LocalAiTranscriptTurn({required this.userText, required this.assistantText});
  final String userText;
  final String assistantText;

  Map<String, String> toMap() => {
        'user_text': userText,
        'assistant_text': assistantText,
      };
}

class LocalAiTranscriptRestoreResult {
  const LocalAiTranscriptRestoreResult({
    required this.transcript,
    required this.retainedTurnCount,
    required this.omittedTurnCount,
    required this.omittedCharacterCount,
    required this.completedTurns,
    required this.omittedCompletedTurnCount,
    required this.omittedCompletedCharacterCount,
  });

  final String transcript;
  final int retainedTurnCount;
  final int omittedTurnCount;
  final int omittedCharacterCount;
  final List<LocalAiTranscriptTurn> completedTurns;
  final int omittedCompletedTurnCount;
  final int omittedCompletedCharacterCount;
}

class LocalAiTranscriptRestorePolicy {
  static const int maxTranscriptCharacters = 10000;
  static const int maxRetainedTurns = 12;
  static const String truncationMarker = '【较早历史已省略，以下为最近内容】\n';

  static LocalAiTranscriptRestoreResult fromMessages(
    List<LocalAiTranscriptMessage> messages,
  ) {
    final turns = <List<LocalAiTranscriptMessage>>[];
    final leadingAssistantMessages = <LocalAiTranscriptMessage>[];
    var pendingTurn = <LocalAiTranscriptMessage>[];
    var pendingTurnHasAssistant = false;
    var omittedTurnCount = 0;
    var omittedCharacterCount = 0;

    void omitPendingTurn() {
      if (pendingTurn.isEmpty) return;
      omittedTurnCount += 1;
      omittedCharacterCount += _serializeTurn(pendingTurn).length;
      pendingTurn = <LocalAiTranscriptMessage>[];
      pendingTurnHasAssistant = false;
    }

    void retainPendingTurn() {
      if (pendingTurn.isEmpty) return;
      if (!pendingTurnHasAssistant) {
        omitPendingTurn();
        return;
      }
      if (turns.isEmpty && leadingAssistantMessages.isNotEmpty) {
        turns.add([...leadingAssistantMessages, ...pendingTurn]);
        leadingAssistantMessages.clear();
      } else {
        turns.add(List<LocalAiTranscriptMessage>.unmodifiable(pendingTurn));
      }
      pendingTurn = <LocalAiTranscriptMessage>[];
      pendingTurnHasAssistant = false;
    }

    for (final message in messages) {
      if (message.text.trim().isEmpty) continue;
      if (message.role == LocalAiTranscriptRole.user) {
        retainPendingTurn();
        pendingTurn = <LocalAiTranscriptMessage>[message];
        pendingTurnHasAssistant = false;
      } else if (pendingTurn.isEmpty) {
        leadingAssistantMessages.add(message);
      } else {
        pendingTurn.add(message);
        pendingTurnHasAssistant = true;
      }
    }
    retainPendingTurn();

    // Assistant-only prelude remains available for diagnostics, but is not
    // promoted into Native memory as a synthetic user/assistant turn.
    if (turns.isEmpty && leadingAssistantMessages.isNotEmpty) {
      turns.add(List<LocalAiTranscriptMessage>.unmodifiable(leadingAssistantMessages));
    }

    final serializedTurns = turns.map(_serializeTurn).toList(growable: false);

    LocalAiTranscriptTurn? toCompletedTurn(List<LocalAiTranscriptMessage> turn) {
      final userIndex = turn.indexWhere((m) => m.role == LocalAiTranscriptRole.user);
      if (userIndex < 0) return null;
      final assistantTexts = turn
          .skip(userIndex + 1)
          .where((m) => m.role == LocalAiTranscriptRole.assistant)
          .map((m) => m.text)
          .toList(growable: false);
      if (assistantTexts.isEmpty) return null;
      return LocalAiTranscriptTurn(
        userText: turn[userIndex].text,
        assistantText: assistantTexts.join('\n'),
      );
    }

    final allCompletedTurns = turns
        .map(toCompletedTurn)
        .whereType<LocalAiTranscriptTurn>()
        .toList(growable: false);

    int joinedLengthFrom(int start) {
      if (start >= serializedTurns.length) return 0;
      var length = serializedTurns.length - start - 1;
      for (var i = start; i < serializedTurns.length; i++) {
        length += serializedTurns[i].length;
      }
      return length;
    }

    var retainedStart = serializedTurns.length;
    while (retainedStart > 0) {
      final candidateStart = retainedStart - 1;
      if (serializedTurns.length - candidateStart > maxRetainedTurns) break;
      final markerLength = (omittedTurnCount + candidateStart) > 0
          ? truncationMarker.length
          : 0;
      if (joinedLengthFrom(candidateStart) + markerLength > maxTranscriptCharacters) {
        break;
      }
      retainedStart = candidateStart;
    }

    for (var i = 0; i < retainedStart; i++) {
      omittedCharacterCount += serializedTurns[i].length;
      omittedTurnCount += 1;
    }

    final retained = serializedTurns.skip(retainedStart).join('\n');
    final transcript = omittedTurnCount > 0 ? '$truncationMarker$retained' : retained;
    if (transcript.length > maxTranscriptCharacters) {
      throw StateError('Bounded Native transcript exceeded its character budget');
    }

    final retainedCompleted = allCompletedTurns.skip(retainedStart).toList(growable: false);
    final omittedCompleted = allCompletedTurns.take(retainedStart).toList(growable: false);
    final omittedCompletedChars = omittedCompleted.fold<int>(
      0,
      (sum, turn) => sum + turn.userText.length + turn.assistantText.length,
    );

    return LocalAiTranscriptRestoreResult(
      transcript: transcript,
      retainedTurnCount: serializedTurns.length - retainedStart,
      omittedTurnCount: omittedTurnCount,
      omittedCharacterCount: omittedCharacterCount,
      completedTurns: List<LocalAiTranscriptTurn>.unmodifiable(retainedCompleted),
      omittedCompletedTurnCount: omittedCompleted.length,
      omittedCompletedCharacterCount: omittedCompletedChars,
    );
  }

  static String _serializeTurn(List<LocalAiTranscriptMessage> turn) =>
      turn.map((message) {
        final role = switch (message.role) {
          LocalAiTranscriptRole.user => '用户',
          LocalAiTranscriptRole.assistant => '助手',
        };
        return '$role：${message.text}';
      }).join('\n');
}
