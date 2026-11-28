package com.nihaisha.nihaisha_app

import java.io.File
import java.security.MessageDigest

/**
 * Streaming integrity helpers for the large on-device Gemma model.
 * The entire model is never loaded into memory to calculate its digest.
 */
object LocalAiModelIntegrityPolicy {
    fun sha256(file: File): String {
        require(file.isFile) { "模型文件不是普通文件" }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") {
            "%02x".format(it.toInt() and 0xff)
        }
    }

    fun matches(actualSha256: String, expectedSha256: String): Boolean =
        actualSha256.equals(expectedSha256, ignoreCase = true)
}
