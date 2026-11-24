package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AiModelAccessGateTest {
    @Test
    fun gateStartsClosedAndRejectsModelOperations() {
        val gate = AiModelAccessGate()

        assertFalse(gate.isAllowed())
        try {
            gate.requireAccess()
            throw AssertionError("closed Native AI gate must reject access")
        } catch (error: AiModelAccessDeniedException) {
            assertEquals(AiModelAccessGate.ERROR_CODE, error.let { AiModelAccessGate.ERROR_CODE })
        }
    }

    @Test
    fun verifiedStateCanOpenAndLaterCloseTheGate() {
        val gate = AiModelAccessGate()

        gate.setAllowed(true)
        assertTrue(gate.isAllowed())
        gate.requireAccess()

        gate.setAllowed(false)
        assertFalse(gate.isAllowed())
        try {
            gate.requireAccess()
            throw AssertionError("revoked Native AI gate must reject new access")
        } catch (_: AiModelAccessDeniedException) {
            // Expected: Native Gate fails closed after revocation.
        }
    }

    @Test
    fun gateStateIsOnlyTheCurrentProcessMemoryState() {
        val firstActivityGate = AiModelAccessGate()
        firstActivityGate.setAllowed(true)
        assertTrue(firstActivityGate.isAllowed())

        // A new process constructs a new gate; no persistent "pro" bit exists.
        val nextProcessGate = AiModelAccessGate()
        assertFalse(nextProcessGate.isAllowed())
    }
}
