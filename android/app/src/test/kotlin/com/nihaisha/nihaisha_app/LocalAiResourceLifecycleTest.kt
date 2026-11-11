package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiResourceLifecycleTest {
    @Test
    fun successfulCloseMarksReleasedAndAllowsReload() {
        val lifecycle = LocalAiResourceLifecycle()
        lifecycle.markReady()

        lifecycle.release { }

        assertEquals(LocalAiResourceLifecycle.State.RELEASED, lifecycle.state)
        lifecycle.ensureLoadAllowed()
        lifecycle.markReady()
        assertEquals(LocalAiResourceLifecycle.State.READY, lifecycle.state)
    }

    @Test
    fun closeFailureMarksUnknownAndBlocksRetryAndCacheDeletion() {
        val lifecycle = LocalAiResourceLifecycle()
        lifecycle.markReady()
        val closeFailure = IllegalStateException("engine close failed")
        var cacheDeleted = false

        val thrown = try {
            lifecycle.release { throw closeFailure }
            cacheDeleted = true
            throw AssertionError("Expected close failure")
        } catch (error: IllegalStateException) {
            error
        }

        assertSame(closeFailure, thrown)
        assertFalse(cacheDeleted)
        assertEquals(LocalAiResourceLifecycle.State.UNKNOWN, lifecycle.state)

        var secondCloseAttempted = false
        val retry = try {
            lifecycle.release { secondCloseAttempted = true }
            cacheDeleted = true
            throw AssertionError("Expected UNKNOWN state to reject retry")
        } catch (error: IllegalStateException) {
            error
        }

        assertTrue(retry.message!!.contains("状态未知"))
        assertFalse(secondCloseAttempted)
        assertFalse(cacheDeleted)
        assertEquals(LocalAiResourceLifecycle.State.UNKNOWN, lifecycle.state)
    }

    @Test
    fun unknownStateBlocksModelReload() {
        val lifecycle = LocalAiResourceLifecycle()
        lifecycle.markReady()
        try {
            lifecycle.release { throw IllegalStateException("conversation close failed") }
            throw AssertionError("Expected close failure")
        } catch (_: IllegalStateException) {
            // Expected: the lifecycle is now UNKNOWN.
        }

        val thrown = try {
            lifecycle.ensureLoadAllowed()
            throw AssertionError("Expected model reload to be blocked")
        } catch (error: IllegalStateException) {
            error
        }
        assertTrue(thrown.message!!.contains("状态未知"))
    }

    @Test
    fun repeatedSuccessfulReleaseIsIdempotent() {
        val lifecycle = LocalAiResourceLifecycle()
        lifecycle.markReady()
        var closeCalls = 0

        lifecycle.release { closeCalls++ }
        lifecycle.release { closeCalls++ }

        assertEquals(1, closeCalls)
        assertEquals(LocalAiResourceLifecycle.State.RELEASED, lifecycle.state)
    }
}
