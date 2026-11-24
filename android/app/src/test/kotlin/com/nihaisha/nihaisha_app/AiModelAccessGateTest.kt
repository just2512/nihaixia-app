package com.nihaisha.nihaisha_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AiModelAccessGateTest {
    @Test
    fun startsClosedAndRejectsWithoutVerifiedAccess() {
        val gate = AiModelAccessGate()

        assertFalse(gate.isEnabled())
        try {
            gate.requireAccess()
            throw AssertionError("closed gate must reject")
        } catch (_: AiModelAccessDeniedException) {
            // Expected fail-closed result.
        }
    }

    @Test
    fun enablingAndDisablingChangesTheOnlyRuntimeDecision() {
        val gate = AiModelAccessGate()

        gate.enable()
        assertTrue(gate.isEnabled())
        gate.requireAccess()

        gate.disable()
        assertFalse(gate.isEnabled())
        try {
            gate.requireAccess()
            throw AssertionError("disabled gate must reject new work")
        } catch (_: AiModelAccessDeniedException) {
            // Expected fail-closed result.
        }
    }

    @Test
    fun aFreshProcessGateNeverInheritsThePreviousInstanceState() {
        val firstProcess = AiModelAccessGate()
        firstProcess.enable()
        val restartedProcess = AiModelAccessGate()

        assertTrue(firstProcess.isEnabled())
        assertFalse(restartedProcess.isEnabled())
    }
}
