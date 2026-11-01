package com.nihaisha.nihaisha_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FirstTurnGpuFallbackPolicyTest {
    private val openClError =
        IllegalStateException("Can not find OpenCL library on this device")

    @Test
    fun retriesOnlyGpuFirstTurnWithKnownOpenClFailure() {
        assertTrue(
            FirstTurnGpuFallbackPolicy.shouldFallback(
                activeBackend = "gpu",
                conversationHasSuccessfulTurn = false,
                error = openClError
            )
        )
    }

    @Test
    fun doesNotRetryAfterAnySuccessfulConversationTurn() {
        assertFalse(
            FirstTurnGpuFallbackPolicy.shouldFallback(
                activeBackend = "gpu",
                conversationHasSuccessfulTurn = true,
                error = openClError
            )
        )
    }

    @Test
    fun doesNotRetryWhenCpuIsAlreadyActive() {
        assertFalse(
            FirstTurnGpuFallbackPolicy.shouldFallback(
                activeBackend = "cpu",
                conversationHasSuccessfulTurn = false,
                error = openClError
            )
        )
    }

    @Test
    fun doesNotRetryForUnrelatedGpuErrors() {
        assertFalse(
            FirstTurnGpuFallbackPolicy.shouldFallback(
                activeBackend = "gpu",
                conversationHasSuccessfulTurn = false,
                error = IllegalStateException("out of memory")
            )
        )
    }

    @Test
    fun findsKnownOpenClFailureInCauseChain() {
        val wrapped = RuntimeException(
            "Native runtime failed",
            IllegalStateException("Can not find OpenCL library on this device")
        )
        assertTrue(
            FirstTurnGpuFallbackPolicy.shouldFallback(
                activeBackend = "GPU",
                conversationHasSuccessfulTurn = false,
                error = wrapped
            )
        )
    }
}
