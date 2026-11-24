package com.nihaisha.nihaisha_app

/**
 * Process-local admission gate for every Native LiteRT model operation.
 *
 * It is intentionally volatile/in-memory only: a process starts closed and
 * Dart must re-verify the signed device-bound Token before opening it.
 */
internal class AiModelAccessGate {
    @Volatile
    private var allowed: Boolean = false

    fun isAllowed(): Boolean = allowed

    fun setAllowed(value: Boolean) {
        allowed = value
    }

    fun requireAccess() {
        if (!allowed) throw AiModelAccessDeniedException()
    }

    companion object {
        const val ERROR_CODE = "AI_ACCESS_REQUIRED"
    }
}

internal class AiModelAccessDeniedException :
    IllegalStateException("Native AI model access is not licensed (ai_access required).")
