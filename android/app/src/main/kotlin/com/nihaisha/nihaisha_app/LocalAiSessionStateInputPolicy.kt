package com.nihaisha.nihaisha_app

/**
 * Validates the optional structured-memory prompt section at the Native
 * boundary. It is bound to the active persisted conversation and never
 * enters the recovery transcript.
 */
internal object LocalAiSessionStateInputPolicy {
    const val maxContextCharacters = 16_000
    const val expectedHeader = "【App 本会话结构化记忆快照 v1】"

    fun validate(
        context: String,
        snapshotConversationId: Long?,
        activeConversationId: Long
    ): String {
        if (context.isBlank()) return ""
        require(activeConversationId > 0L) {
            "SESSION_STATE_ACTIVE_CONVERSATION_ID_INVALID"
        }
        require(snapshotConversationId == activeConversationId) {
            "SESSION_STATE_CONVERSATION_ID_MISMATCH"
        }
        require(context.length <= maxContextCharacters) {
            "SESSION_STATE_CONTEXT_TOO_LARGE"
        }
        require(context.startsWith(expectedHeader)) {
            "SESSION_STATE_CONTEXT_HEADER_INVALID"
        }
        return context
    }
}
