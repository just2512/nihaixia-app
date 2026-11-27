package com.nihaisha.nihaisha_app

import java.io.File

/**
 * Pure validation rules for multimodal files handed to LiteRT-LM.
 *
 * The caller must pass canonical paths so symlinks and traversal are resolved
 * before the cache-directory boundary is checked.
 */
internal object LocalAiAttachmentPolicy {
    const val MAX_FILE_SIZE_BYTES: Long = 15L * 1024L * 1024L

    fun validationError(
        filePath: String,
        cacheRootPath: String,
        isFile: Boolean,
        sizeBytes: Long,
        kind: String
    ): String? {
        val cachePrefix = cacheRootPath.trimEnd(File.separatorChar) + File.separator
        if (!filePath.startsWith(cachePrefix) || !isFile || sizeBytes <= 0L) {
            return "$kind 文件无效或不在应用缓存目录内"
        }
        if (sizeBytes > MAX_FILE_SIZE_BYTES) {
            return "$kind 文件超过 15 MB，请重新选择"
        }
        return null
    }
}
