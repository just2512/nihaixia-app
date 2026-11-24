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

        gate.enable(gate.currentEpoch())
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
    fun revokeInvalidatesAnEnableTaskThatWasAlreadyQueued() {
        val gate = AiModelAccessGate()
        val queuedEnableEpoch = gate.currentEpoch()

        gate.disable()

        try {
            gate.enable(queuedEnableEpoch)
            throw AssertionError("superseded enable must not reopen the gate")
        } catch (_: AiModelAccessSyncSupersededException) {
            // Expected stale task rejection.
        }
        assertFalse(gate.isEnabled())
    }

    @Test
    fun aFreshProcessGateNeverInheritsThePreviousInstanceState() {
        val firstProcess = AiModelAccessGate()
        firstProcess.enable(firstProcess.currentEpoch())
        val restartedProcess = AiModelAccessGate()

        assertTrue(firstProcess.isEnabled())
        assertFalse(restartedProcess.isEnabled())
    }
}
