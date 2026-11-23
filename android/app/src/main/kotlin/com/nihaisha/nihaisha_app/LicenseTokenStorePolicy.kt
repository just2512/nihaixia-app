package com.nihaisha.nihaisha_app

import java.nio.charset.StandardCharsets

internal object LicenseTokenStorePolicy {
    const val MAX_TOKEN_BYTES = 16_384

    fun isValidStoredToken(token: String?): Boolean {
        if (token.isNullOrEmpty() || token != token.trim()) return false
        if (token.toByteArray(StandardCharsets.UTF_8).size > MAX_TOKEN_BYTES) return false
        return token.matches(Regex("^YANJI1\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$"))
    }

    fun isValidStoredTokenBytes(bytes: ByteArray): Boolean =
        bytes.isNotEmpty() && bytes.size <= MAX_TOKEN_BYTES
}
