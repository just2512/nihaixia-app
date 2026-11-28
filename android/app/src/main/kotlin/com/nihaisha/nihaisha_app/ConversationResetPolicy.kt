package com.nihaisha.nihaisha_app

/**
 * Rebuild a conversation without leaving a live Engine behind when reset fails.
 *
 * Callers must detach their old Conversation reference before invoking this
 * helper and clear their Engine reference if this method throws. If Engine
 * release itself fails, [onEngineReleaseFailure] must make the whole process
 * unavailable because a second Engine cannot safely be initialized.
 */
internal object ConversationResetPolicy {
    fun <T> recreateConversation(
        closePrevious: () -> Unit,
        createNext: () -> T,
        closeEngine: () -> Unit,
        onEngineReleaseFailure: (Throwable) -> Unit
    ): T {
        try {
            closePrevious()
        } catch (error: Throwable) {
            closeEngineAfterFailure(error, closeEngine, onEngineReleaseFailure)
            throw IllegalStateException(
                "旧问诊会话无法安全关闭；模型引擎已释放，需要重新加载",
                error
            )
        }

        return try {
            createNext()
        } catch (error: Throwable) {
            closeEngineAfterFailure(error, closeEngine, onEngineReleaseFailure)
            throw IllegalStateException(
                "无法创建新的问诊会话；模型引擎已释放，需要重新加载",
                error
            )
        }
    }

    private fun closeEngineAfterFailure(
        primaryError: Throwable,
        closeEngine: () -> Unit,
        onEngineReleaseFailure: (Throwable) -> Unit
    ) {
        try {
            closeEngine()
        } catch (closeError: Throwable) {
            if (closeError !== primaryError) {
                primaryError.addSuppressed(closeError)
            }
            onEngineReleaseFailure(closeError)
        }
    }
}
