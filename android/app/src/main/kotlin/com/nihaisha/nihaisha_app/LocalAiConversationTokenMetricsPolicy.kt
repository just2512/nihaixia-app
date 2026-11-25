package com.nihaisha.nihaisha_app

/**
 * Describes what is actually known about the active LiteRT-LM context.
 *
 * This reports measurements only. It intentionally does not choose a usage
 * percentage, token reserve, compaction threshold, or automatic reset policy.
 */
internal enum class LocalAiConversationTokenMetricsStatus {
    MEASURED,
    TOKEN_COUNT_ONLY,
    MODEL_LIMIT_ONLY,
    UNKNOWN
}

internal data class LocalAiConversationTokenMetricsSnapshot(
    val status: LocalAiConversationTokenMetricsStatus,
    val conversationTokenCount: Int?,
    val modelMaxContextTokens: Int?
) {
    fun toMethodChannelMap(): Map<String, Any> = buildMap {
        put("status", status.name)
        put("unit", "KV_CACHE_TOKENS")
        conversationTokenCount?.let { put("conversationTokenCount", it) }
        modelMaxContextTokens?.let { put("modelMaxContextTokens", it) }
    }
}

internal object LocalAiConversationTokenMetricsPolicy {
    fun snapshot(
        conversationTokenCount: Int?,
        modelMaxContextTokens: Int?
    ): LocalAiConversationTokenMetricsSnapshot {
        val validTokenCount = conversationTokenCount?.takeIf { it >= 0 }
        val validModelLimit = modelMaxContextTokens?.takeIf { it > 0 }
        val status = when {
            validTokenCount != null && validModelLimit != null ->
                LocalAiConversationTokenMetricsStatus.MEASURED
            validTokenCount != null ->
                LocalAiConversationTokenMetricsStatus.TOKEN_COUNT_ONLY
            validModelLimit != null ->
                LocalAiConversationTokenMetricsStatus.MODEL_LIMIT_ONLY
            else ->
                LocalAiConversationTokenMetricsStatus.UNKNOWN
        }
        return LocalAiConversationTokenMetricsSnapshot(
            status = status,
            conversationTokenCount = validTokenCount,
            modelMaxContextTokens = validModelLimit
        )
    }
}
