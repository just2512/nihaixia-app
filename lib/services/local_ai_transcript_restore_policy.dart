/// Bounds the transcript replayed when a persisted assistant conversation
/// is restored into the Native LiteRT-LM conversation.
///
/// The budget is measured in Dart UTF-16 code units, matching Kotlin String.
/// Only complete user/assistant turns are retained; a message is never cut
/// mid-sentence, and an incomplete final turn is never replayed as complete.
enum LocalAiTranscriptRole { user, assistant }

class LocalAiTranscriptMessage {
  const LocalAiTranscriptMessage({
    required this.role,
    required this.text,
  });

  final LocalAiTranscriptRole role;
  final String text;
}

class LocalAiTranscriptRestoreResult {
  const LocalAiTranscriptRestoreResult({
    required this.transcript,
    required this.retainedTurnCount,
    required this.omittedTurnCount,
    required this.omittedCharacterCount,
  });

  final String transcript;
  final int retainedTurnCount;
  final int omittedTurnCount;
  final int omittedCharacterCount;
}

class LocalAiTranscriptRestorePolicy {
  static const int maxTranscriptCharacters = 10000;
  static const String truncationMarker = '【较早历史已省略，以下为最近内容】\n';

  /// Replays only complete turns, preserving the newest turns first.
  ///
  /// Consecutive assistant messages belong to the preceding user turn.
  /// Leading assistant-only messages (for example, the welcome message) are
  /// attached to the first complete turn. An unfinished user turn is omitted.
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
        turns.add([
          ...leadingAssistantMessages,
          ...pendingTurn,
        ]);
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

    // A transcript that contains only assistant-side prelude messages remains
    // useful for restoring the initial conversation state.
    if (turns.isEmpty && leadingAssistantMessages.isNotEmpty) {
      turns.add(List<LocalAiTranscriptMessage>.unmodifiable(
        leadingAssistantMessages,
      ));
    }

    final serializedTurns = turns.map(_serializeTurn).toList(growable: false);

    int joinedLengthFrom(int start) {
      if (start >= serializedTurns.length) return 0;
      var length = serializedTurns.length - start - 1;
      for (var index = start; index < serializedTurns.length; index++) {
        length += serializedTurns[index].length;
      }
      return length;
    }

    var retainedStart = serializedTurns.length;
    while (retainedStart > 0) {
      final candidateStart = retainedStart - 1;
      // The marker is part of the same budget. It is needed either when an
      // incomplete turn was omitted or when any older complete turn is left
      // out by retaining only this suffix.
      final candidateOmittedTurnCount = omittedTurnCount + candidateStart;
      final markerLength = candidateOmittedTurnCount > 0
          ? truncationMarker.length
          : 0;
      if (joinedLengthFrom(candidateStart) + markerLength >
          maxTranscriptCharacters) {
        break;
      }
      retainedStart = candidateStart;
    }

    for (var index = 0; index < retainedStart; index++) {
      omittedCharacterCount += serializedTurns[index].length;
      omittedTurnCount += 1;
    }

    final retained = serializedTurns.skip(retainedStart).join('\\n');
    final transcript = omittedTurnCount > 0
        ? '$truncationMarker$retained'
        : retained;
    if (transcript.length > maxTranscriptCharacters) {
      throw StateError('Bounded Native transcript exceeded its character budget');
    }

    return LocalAiTranscriptRestoreResult(
      transcript: transcript,
      retainedTurnCount: serializedTurns.length - retainedStart,
      omittedTurnCount: omittedTurnCount,
      omittedCharacterCount: omittedCharacterCount,
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
