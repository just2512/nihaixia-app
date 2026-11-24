package com.nihaisha.nihaisha_app

/**
 * Process-memory authorization gate for every Native LiteRT model operation.
 *
 * The process singleton is initialized closed. It is never persisted; the
 * verified Token must reopen it after every process start.
 */
internal class AiModelAccessGate(initiallyEnabled: Boolean = false) {
    @Volatile
    private var enabled = initiallyEnabled

    fun isEnabled(): Boolean = enabled

    fun enable() {
        enabled = true
    }

    /** Closes synchronously so queued model work fails before it can start. */
    fun disable() {
        enabled = false
    }

    fun requireAccess() {
        if (!enabled) throw AiModelAccessDeniedException()
    }

    companion object {
        val process: AiModelAccessGate = AiModelAccessGate()
    }
}

internal class AiModelAccessDeniedException :
    IllegalStateException("AI_ACCESS_REQUIRED: 需要有效的研纪专业版 AI 授权")
