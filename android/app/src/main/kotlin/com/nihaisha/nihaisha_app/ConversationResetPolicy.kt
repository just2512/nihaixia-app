package com.nihaisha.nihaisha_app

/**
 * Rebuild a conversation without leaving a live Engine behind when reset fails.
 *
 * Callers must detach their old Conversation reference before invoking this
 * helper and clear their Engine reference if this method throws.
 */
internal object ConversationResetPolicy {
    fun <T> recreateConversation(
        closePrevious: () -> Unit,
        createNext: () -> T,
        closeEngine: () -> Unit
    ): T {
        try {
            closePrevious()
        } catch (error: Exception) {
            closeEngineAfterFailure(error, closeEngine)
            throw IllegalStateException(
                "旧问诊会话无法安全关闭；模型引擎已释放，需要重新加载",
                error
            )
        }

        return try {
            createNext()
        } catch (error: Exception) {
            closeEngineAfterFailure(error, closeEngine)
            throw IllegalStateException(
                "无法创建新的问诊会话；模型引擎已释放，需要重新加载",
                error
            )
        }
    }

    private fun closeEngineAfterFailure(
        primaryError: Exception,
        closeEngine: () -> Unit
    ) {
        try {
            closeEngine()
        } catch (closeError: Exception) {
            if (closeError !== primaryError) {
                primaryError.addSuppressed(closeError)
            }
        }
    }
}
