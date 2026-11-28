package com.nihaisha.nihaisha_app

/**
 * Process-memory authorization gate for every Native LiteRT model operation.
 *
 * The process singleton is initialized closed. It is never persisted; the
 * verified Token must reopen it after every process start.
 *
 * A monotonically increasing epoch prevents an older queued enable request
 * from reopening the gate after a newer disable request has synchronously
 * revoked access.
 */
internal class AiModelAccessGate(initiallyEnabled: Boolean = false) {
    private val lock = Any()

    @Volatile
    private var enabled = initiallyEnabled
    private var epoch = 0L

    fun isEnabled(): Boolean = enabled

    fun currentEpoch(): Long = synchronized(lock) { epoch }

    fun enable(expectedEpoch: Long) = synchronized(lock) {
        if (expectedEpoch != epoch) {
            throw AiModelAccessSyncSupersededException()
        }
        enabled = true
    }

    /** Closes synchronously so queued/new inference observes false immediately. */
    fun disable() = synchronized(lock) {
        enabled = false
        epoch += 1
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

internal class AiModelAccessSyncSupersededException :
    IllegalStateException("AI_ACCESS_SYNC_SUPERSEDED: 授权状态同步已被更新的状态取代")
