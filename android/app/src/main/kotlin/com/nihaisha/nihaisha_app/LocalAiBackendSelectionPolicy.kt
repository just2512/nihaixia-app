package com.nihaisha.nihaisha_app

/**
 * Restricts the explicit CPU backend override to debuggable builds.
 * Production builds always retain the normal GPU-first selection policy.
 */
internal object LocalAiBackendSelectionPolicy {
    fun shouldForceCpu(debuggableBuild: Boolean, requested: Boolean): Boolean =
        debuggableBuild && requested
}
