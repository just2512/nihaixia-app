package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiConversationSessionIdentityTest {
    @Test
    fun firstConversationRequiresResetUntilSuccessfullyActivated() {
        val identity = LocalAiConversationSessionIdentity()

        assertTrue(identity.requiresReset(41L))
        identity.activate(41L)
        assertEquals(41L, identity.activeId())
        assertFalse(identity.requiresReset(41L))
    }

    @Test
    fun switchingToAnotherSqliteConversationRequiresReset() {
        val identity = LocalAiConversationSessionIdentity()
        identity.activate(41L)

        assertTrue(identity.requiresReset(42L))
        identity.activate(42L)

        assertEquals(42L, identity.activeId())
        assertFalse(identity.requiresReset(42L))
    }

    @Test
    fun clearingIdentityForcesNextConversationToStartClean() {
        val identity = LocalAiConversationSessionIdentity()
        identity.activate(41L)

        identity.clear()

        assertEquals(null, identity.activeId())
        assertTrue(identity.requiresReset(41L))
    }

    @Test
    fun rejectsMissingOrNonPositiveConversationIds() {
        val identity = LocalAiConversationSessionIdentity()

        assertThrows(IllegalArgumentException::class.java) {
            identity.requiresReset(0L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            identity.requiresReset(-1L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            identity.activate(0L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            identity.activate(-1L)
        }
        assertEquals(null, identity.activeId())
    }

    @Test
    fun failedActivationDoesNotReplacePreviouslyActiveIdentity() {
        val identity = LocalAiConversationSessionIdentity()
        identity.activate(41L)

        assertThrows(IllegalArgumentException::class.java) {
            identity.activate(0L)
        }

        assertEquals(41L, identity.activeId())
        assertFalse(identity.requiresReset(41L))
    }
}
