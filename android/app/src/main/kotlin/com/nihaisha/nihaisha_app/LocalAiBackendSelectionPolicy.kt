package com.nihaisha.nihaisha_app

/**
 * Resolves the persisted, user-selectable E4B backend.
 *
 * The normal preference is available in Debug and Release builds. The
 * historical Intent override is accepted only in debuggable builds and only
 * before the user has explicitly saved a backend choice.
 */
internal object LocalAiBackendSelectionPolicy {
    const val GPU = "gpu"
    const val CPU = "cpu"

    fun parseRequestedBackend(value: String?): String? =
        when (value?.trim()?.lowercase()) {
            GPU -> GPU
            CPU -> CPU
            else -> null
        }

    fun normalizePreference(value: String?): String =
        parseRequestedBackend(value) ?: GPU

    fun shouldForceCpu(debuggableBuild: Boolean, requested: Boolean): Boolean =
        debuggableBuild && requested

    fun resolveBackend(
        preferredBackend: String?,
        hasUserPreference: Boolean,
        debuggableBuild: Boolean,
        debugForceCpu: Boolean
    ): String {
        if (!hasUserPreference && shouldForceCpu(debuggableBuild, debugForceCpu)) {
            return CPU
        }
        return normalizePreference(preferredBackend)
    }
}
