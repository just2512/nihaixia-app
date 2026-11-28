package com.nihaisha.nihaisha_app

/**
 * Keep automatic GPU recovery narrow. Only a known first-turn OpenCL library
 * error can be retried on CPU; other errors or established conversation
 * histories must never be replayed automatically.
 */
internal object FirstTurnGpuFallbackPolicy {
    private const val missingOpenClMessage =
        "Can not find OpenCL library on this device"

    fun shouldFallback(
        activeBackend: String,
        conversationHasSuccessfulTurn: Boolean,
        error: Throwable
    ): Boolean {
        if (!activeBackend.equals("gpu", ignoreCase = true)) return false
        if (conversationHasSuccessfulTurn) return false
        return hasMissingOpenClMessage(error)
    }

    private fun hasMissingOpenClMessage(error: Throwable): Boolean {
        val seen = java.util.Collections.newSetFromMap(
            java.util.IdentityHashMap<Throwable, Boolean>()
        )
        var current: Throwable? = error
        while (current != null && seen.add(current)) {
            if (current.message?.contains(missingOpenClMessage, ignoreCase = true) == true) {
                return true
            }
            current = current.cause
        }
        return false
    }
}
