package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class ConversationResourceReleasePolicyTest {
    @Test
    fun closesConversationBeforeEngine() {
        val events = mutableListOf<String>()

        ConversationResourceReleasePolicy.closeBoth(
            closeConversation = { events += "conversation.close" },
            closeEngine = { events += "engine.close" }
        )

        assertEquals(listOf("conversation.close", "engine.close"), events)
    }

    @Test
    fun stillClosesEngineWhenConversationCloseFails() {
        val conversationError = IllegalStateException("conversation close failed")
        val events = mutableListOf<String>()

        val thrown = try {
            ConversationResourceReleasePolicy.closeBoth(
                closeConversation = {
                    events += "conversation.close"
                    throw conversationError
                },
                closeEngine = { events += "engine.close" }
            )
            throw AssertionError("Expected release to fail")
        } catch (error: IllegalStateException) {
            error
        }

        assertSame(conversationError, thrown.cause)
        assertEquals(listOf("conversation.close", "engine.close"), events)
    }

    @Test
    fun preservesConversationFailureAndSuppressesEngineFailure() {
        val conversationError = IllegalStateException("conversation close failed")
        val engineError = IllegalStateException("engine close failed")

        val thrown = try {
            ConversationResourceReleasePolicy.closeBoth(
                closeConversation = { throw conversationError },
                closeEngine = { throw engineError }
            )
            throw AssertionError("Expected release to fail")
        } catch (error: IllegalStateException) {
            error
        }

        assertSame(conversationError, thrown.cause)
        assertEquals(listOf(engineError), conversationError.suppressed.toList())
    }
}
