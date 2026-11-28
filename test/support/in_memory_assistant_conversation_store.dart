import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';

/// Isolated in-memory persistence for contextual UI widget tests. It keeps
/// assistant initialization deterministic and avoids coupling these tests to
/// SQLite transaction timers.
class InMemoryAssistantConversationStore implements AssistantConversationStore {
  int _nextConversationId = 1;
  int _nextMessageId = 1;
  final Map<int, Map<String, Object?>> _conversations = {};
  final Map<int, List<Map<String, Object?>>> _messages = {};
  final Map<int, TcmInterviewTaskState> _taskStates = {};

  @override
  Future<int> createAssistantConversation({
    String title = '新对话',
    String mode = 'general',
  }) async {
    final id = _nextConversationId++;
    _conversations[id] = {'id': id, 'title': title, 'mode': mode};
    _messages[id] = [];
    return id;
  }

  @override
  Future<int> saveAssistantMessage({
    required int conversationId,
    required String role,
    required String content,
    String? metadata,
    String? invocationKey,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (invocationKey != null &&
        (normalizedRole != 'tool' ||
            invocationKey.trim().isEmpty ||
            invocationKey != invocationKey.trim() ||
            invocationKey.length > 160)) {
      throw ArgumentError.value(invocationKey, 'invocationKey');
    }
    final rows = _messages[conversationId] ?? const [];
    if (invocationKey != null &&
        rows.any((row) => row['invocation_key'] == invocationKey)) {
      throw StateError('Assistant invocation key already exists');
    }
    final id = _nextMessageId++;
    (_messages[conversationId] ??= []).add({
      'id': id,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'metadata': metadata,
      'invocation_key': invocationKey,
    });
    return id;
  }

  @override
  Future<List<int>> saveAssistantMessagesAtomically({
    required int conversationId,
    required List<AssistantMessageDraft> messages,
  }) async {
    final ids = <int>[];
    for (final message in messages) {
      ids.add(await saveAssistantMessage(
        conversationId: conversationId,
        role: message.role,
        content: message.content,
        metadata: message.metadata,
      ));
    }
    return ids;
  }

  @override
  Future<int> saveAssistantTurn({
    required int conversationId,
    String? userContent,
    String? userMetadata,
    required String assistantContent,
    String? assistantMetadata,
  }) async {
    if (userContent != null) {
      await saveAssistantMessage(
        conversationId: conversationId,
        role: 'user',
        content: userContent,
        metadata: userMetadata,
      );
    }
    return saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: assistantContent,
      metadata: assistantMetadata,
    );
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  }) async {
    final rows = _conversations.values
        .map((row) => Map<String, Object?>.from(row))
        .toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return limit == null ? rows : rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  }) async {
    return (_messages[conversationId] ?? const [])
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantMessagesForSessionState({
    required int conversationId,
    required int limit,
  }) async {
    if (limit <= 0 ||
        limit > AssistantConversationStore.maxSessionStateReadRows) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Must be between 1 and ${AssistantConversationStore.maxSessionStateReadRows}',
      );
    }
    final visibleRows = (_messages[conversationId] ?? const [])
        .where((row) {
          final role = row['role'];
          return role == 'user' || role == 'assistant';
        })
        .map((row) => Map<String, Object?>.from(row))
        .toList()
      ..sort((left, right) =>
          (left['id'] as int).compareTo(right['id'] as int));
    final start = visibleRows.length > limit ? visibleRows.length - limit : 0;
    return visibleRows.sublist(start);
  }

  @override
  Future<void> saveTcmInterviewTaskState({
    required int conversationId,
    required TcmInterviewTaskState state,
  }) async {
    _taskStates[conversationId] = state;
  }

  @override
  Future<TcmInterviewTaskState?> getTcmInterviewTaskState({
    required int conversationId,
  }) async =>
      _taskStates[conversationId];

  @override
  Future<void> deleteAssistantConversations(List<int> conversationIds) async {
    for (final id in conversationIds) {
      _conversations.remove(id);
      _messages.remove(id);
      _taskStates.remove(id);
    }
  }
}
