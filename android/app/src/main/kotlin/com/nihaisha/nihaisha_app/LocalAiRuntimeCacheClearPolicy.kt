package com.nihaisha.nihaisha_app

import java.io.File

internal data class LocalAiRuntimeCacheClearResult(
    val runtimeReleased: Boolean,
    val cacheDeleted: Boolean,
    val modelFileExists: Boolean,
    val errorCode: String?
) {
    fun toMap(): Map<String, Any> = buildMap {
        put("runtimeReleased", runtimeReleased)
        put("cacheDeleted", cacheDeleted)
        put("modelFileExists", modelFileExists)
        errorCode?.let { put("errorCode", it) }
    }
}

/**
 * Enforces the destructive-operation order: release native runtime first,
 * then delete only the LiteRT-LM cache directory. The installed model file is
 * outside this directory and is never a deletion target.
 */
internal object LocalAiRuntimeCacheClearPolicy {
    fun clear(
        runtimeCacheDirectory: File,
        modelFile: File,
        releaseRuntime: () -> Unit
    ): LocalAiRuntimeCacheClearResult {
        try {
            releaseRuntime()
        } catch (_: Exception) {
            // A cache may still be mapped by a live Engine/Conversation.
            // Keep it intact and report a partial result instead of deleting.
            return LocalAiRuntimeCacheClearResult(
                runtimeReleased = false,
                cacheDeleted = false,
                modelFileExists = modelFile.isFile,
                errorCode = "RUNTIME_RELEASE_FAILED"
            )
        }

        val deleted = if (!runtimeCacheDirectory.exists()) {
            true
        } else {
            runtimeCacheDirectory.deleteRecursively() && !runtimeCacheDirectory.exists()
        }
        return LocalAiRuntimeCacheClearResult(
            runtimeReleased = true,
            cacheDeleted = deleted,
            modelFileExists = modelFile.isFile,
            errorCode = if (deleted) null else "CACHE_DELETE_FAILED"
        )
    }
}
