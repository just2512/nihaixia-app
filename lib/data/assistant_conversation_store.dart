import '../models/tcm_interview_task_state.dart';

/// Persistence boundary for the unified assistant's conversation history.
abstract interface class AssistantConversationStore {
  Future<int> createAssistantConversation({
    String title = '新对话',
    String mode = 'general',
  });

  Future<int> saveAssistantMessage({
    required int conversationId,
    required String role,
    required String content,
    String? metadata,
  });

  /// Atomically persists the user/assistant pair for one successful turn.
  /// [userContent] may be null for assistant-only system turns.
  Future<int> saveAssistantTurn({
    required int conversationId,
    String? userContent,
    String? userMetadata,
    required String assistantContent,
    String? assistantMetadata,
  });

  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  });

  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  });

  Future<void> saveTcmInterviewTaskState({
    required int conversationId,
    required TcmInterviewTaskState state,
  });

  Future<TcmInterviewTaskState?> getTcmInterviewTaskState({
    required int conversationId,
  });

  Future<void> deleteAssistantConversations(List<int> conversationIds);
}
