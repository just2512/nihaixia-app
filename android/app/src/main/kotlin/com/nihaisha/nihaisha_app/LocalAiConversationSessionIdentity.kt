package com.nihaisha.nihaisha_app

/**
 * Tracks which SQLite conversation owns the in-memory Native Conversation.
 *
 * This policy is only accessed from MainActivity's serialized AI task queue.
 * It deliberately stores an ID, not transcript content or user metadata.
 */
internal class LocalAiConversationSessionIdentity {
    private var activeConversationId: Long? = null

    fun requiresReset(requestedConversationId: Long): Boolean {
        require(requestedConversationId > 0L) {
            "Native conversation ID must be a positive SQLite row ID"
        }
        return activeConversationId != requestedConversationId
    }

    fun activate(conversationId: Long) {
        require(conversationId > 0L) {
            "Native conversation ID must be a positive SQLite row ID"
        }
        activeConversationId = conversationId
    }

    fun clear() {
        activeConversationId = null
    }

    fun activeId(): Long? = activeConversationId
}
