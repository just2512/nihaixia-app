package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LocalAiSessionStateInputPolicyTest {
    private val validContext =
        LocalAiSessionStateInputPolicy.expectedHeader + "\nstatus=RESTORED"

    @Test
    fun acceptsSnapshotBoundToTheActiveConversation() {
        assertEquals(
            validContext,
            LocalAiSessionStateInputPolicy.validate(validContext, 42L, 42L)
        )
    }

    @Test
    fun ignoresAnAbsentOptionalSnapshotForLegacyCallers() {
        assertEquals("", LocalAiSessionStateInputPolicy.validate("", null, 42L))
    }

    @Test
    fun rejectsCrossSessionSnapshotIds() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiSessionStateInputPolicy.validate(validContext, 41L, 42L)
        }
    }

    @Test
    fun rejectsMissingSnapshotOwnerWhenContextExists() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiSessionStateInputPolicy.validate(validContext, null, 42L)
        }
    }

    @Test
    fun rejectsOversizedPromptSections() {
        val oversized = LocalAiSessionStateInputPolicy.expectedHeader +
            "x".repeat(LocalAiSessionStateInputPolicy.maxContextCharacters)
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiSessionStateInputPolicy.validate(oversized, 42L, 42L)
        }
    }

    @Test
    fun rejectsUnrecognizedPromptSectionHeaders() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiSessionStateInputPolicy.validate("not a snapshot", 42L, 42L)
        }
    }
}
