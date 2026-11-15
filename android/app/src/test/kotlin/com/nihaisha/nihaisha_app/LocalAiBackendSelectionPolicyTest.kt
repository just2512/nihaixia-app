package com.nihaisha.nihaisha_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiBackendSelectionPolicyTest {
    @Test
    fun debuggableBuildCanExplicitlySelectCpu() {
        assertTrue(
            LocalAiBackendSelectionPolicy.shouldForceCpu(
                debuggableBuild = true,
                requested = true
            )
        )
    }

    @Test
    fun releaseBuildIgnoresCpuOverrideExtra() {
        assertFalse(
            LocalAiBackendSelectionPolicy.shouldForceCpu(
                debuggableBuild = false,
                requested = true
            )
        )
    }

    @Test
    fun debugBuildRemainsGpuFirstWithoutExplicitRequest() {
        assertFalse(
            LocalAiBackendSelectionPolicy.shouldForceCpu(
                debuggableBuild = true,
                requested = false
            )
        )
    }
}
