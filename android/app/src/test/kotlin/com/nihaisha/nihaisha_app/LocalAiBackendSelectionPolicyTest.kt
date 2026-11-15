package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiBackendSelectionPolicyTest {
    @Test
    fun acceptsOnlyExplicitGpuOrCpuUserChoices() {
        assertEquals("gpu", LocalAiBackendSelectionPolicy.parseRequestedBackend("GPU"))
        assertEquals("cpu", LocalAiBackendSelectionPolicy.parseRequestedBackend(" cpu "))
        assertNull(LocalAiBackendSelectionPolicy.parseRequestedBackend("auto"))
        assertNull(LocalAiBackendSelectionPolicy.parseRequestedBackend(null))
    }

    @Test
    fun missingOrInvalidStoredPreferenceDefaultsToGpu() {
        assertEquals("gpu", LocalAiBackendSelectionPolicy.normalizePreference(null))
        assertEquals("gpu", LocalAiBackendSelectionPolicy.normalizePreference("invalid"))
    }

    @Test
    fun releaseBuildHonorsExplicitCpuPreference() {
        assertEquals(
            "cpu",
            LocalAiBackendSelectionPolicy.resolveBackend(
                preferredBackend = "cpu",
                debuggableBuild = false,
                debugForceCpu = false
            )
        )
    }

    @Test
    fun releaseBuildHonorsExplicitGpuPreference() {
        assertEquals(
            "gpu",
            LocalAiBackendSelectionPolicy.resolveBackend(
                preferredBackend = "gpu",
                debuggableBuild = false,
                debugForceCpu = false
            )
        )
    }

    @Test
    fun debugIntentCanStillForceCpuForAcceptance() {
        assertEquals(
            "cpu",
            LocalAiBackendSelectionPolicy.resolveBackend(
                preferredBackend = "gpu",
                debuggableBuild = true,
                debugForceCpu = true
            )
        )
    }

    @Test
    fun releaseBuildIgnoresDebugIntentOverride() {
        assertEquals(
            "gpu",
            LocalAiBackendSelectionPolicy.resolveBackend(
                preferredBackend = "gpu",
                debuggableBuild = false,
                debugForceCpu = true
            )
        )
    }

    @Test
    fun debugIntentDoesNotForceCpuInReleaseBuilds() {
        assertFalse(
            LocalAiBackendSelectionPolicy.shouldForceCpu(
                debuggableBuild = false,
                requested = true
            )
        )
        assertTrue(
            LocalAiBackendSelectionPolicy.shouldForceCpu(
                debuggableBuild = true,
                requested = true
            )
        )
    }
}
