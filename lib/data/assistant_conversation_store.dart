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

  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  });

  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  });

  Future<void> deleteAssistantConversations(List<int> conversationIds);
}
