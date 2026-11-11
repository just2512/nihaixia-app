package com.nihaisha.nihaisha_app

/**
 * Tracks whether native Engine/Conversation resources are known to be safe.
 *
 * A close exception is ambiguous: the resource may have been partially closed.
 * The same object must not be closed again, and cache files must not be deleted
 * or a replacement Engine loaded until the process restarts.
 */
internal class LocalAiResourceLifecycle {
    enum class State { RELEASED, READY, UNKNOWN }

    var state: State = State.RELEASED
        private set

    fun ensureLoadAllowed() {
        check(state != State.UNKNOWN) {
            "本地模型资源释放状态未知，请重启应用后重试"
        }
    }

    fun markReady() {
        ensureLoadAllowed()
        state = State.READY
    }

    fun release(closeResources: () -> Unit) {
        check(state != State.UNKNOWN) {
            "本地模型资源释放状态未知，禁止重复关闭或删除运行缓存"
        }
        if (state == State.RELEASED) return
        try {
            closeResources()
            state = State.RELEASED
        } catch (error: Exception) {
            state = State.UNKNOWN
            throw error
        }
    }
}
