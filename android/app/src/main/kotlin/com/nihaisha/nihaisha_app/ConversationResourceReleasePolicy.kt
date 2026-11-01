package com.nihaisha.nihaisha_app

/**
 * Attempts to close both native resources and preserves every close failure.
 * Conversation is always closed before Engine.
 */
internal object ConversationResourceReleasePolicy {
    fun closeBoth(
        closeConversation: () -> Unit,
        closeEngine: () -> Unit
    ) {
        var failure: Exception? = null
        try {
            closeConversation()
        } catch (error: Exception) {
            failure = error
        }

        try {
            closeEngine()
        } catch (error: Exception) {
            if (failure == null) {
                failure = error
            } else if (error !== failure) {
                failure.addSuppressed(error)
            }
        }

        failure?.let {
            throw IllegalStateException("本地模型资源释放失败", it)
        }
    }
}
