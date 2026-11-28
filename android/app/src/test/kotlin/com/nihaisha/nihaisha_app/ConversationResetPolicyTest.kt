package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Test

class ConversationResetPolicyTest {
    @Test
    fun closesPreviousConversationBeforeCreatingReplacement() {
        val events = mutableListOf<String>()

        val result = ConversationResetPolicy.recreateConversation(
            closePrevious = { events += "conversation.close" },
            createNext = {
                events += "conversation.create"
                "new-conversation"
            },
            closeEngine = { events += "engine.close" },
            onEngineReleaseFailure = { throw AssertionError("unexpected engine release failure") }
        )

        assertEquals("new-conversation", result)
        assertEquals(listOf("conversation.close", "conversation.create"), events)
    }

    @Test
    fun closesEngineAndSkipsCreationWhenPreviousCloseFails() {
        val closeError = IllegalStateException("conversation close failed")
        val engineCloseError = IllegalStateException("engine close failed")
        val events = mutableListOf<String>()
        val releaseFailures = mutableListOf<Throwable>()

        val thrown = try {
            ConversationResetPolicy.recreateConversation(
                closePrevious = {
                    events += "conversation.close"
                    throw closeError
                },
                createNext = {
                    events += "conversation.create"
                    "must-not-be-created"
                },
                closeEngine = {
                    events += "engine.close"
                    throw engineCloseError
                },
                onEngineReleaseFailure = { releaseFailures += it }
            )
            throw AssertionError("Expected reset to fail")
        } catch (error: IllegalStateException) {
            error
        }

        assertSame(closeError, thrown.cause)
        assertEquals(listOf(engineCloseError), closeError.suppressed.toList())
        assertEquals(listOf(engineCloseError), releaseFailures)
        assertEquals(listOf("conversation.close", "engine.close"), events)
    }

    @Test
    fun closesEngineWhenReplacementCreationFails() {
        val createError = IllegalStateException("conversation create failed")
        val events = mutableListOf<String>()

        val thrown = try {
            ConversationResetPolicy.recreateConversation(
                closePrevious = { events += "conversation.close" },
                createNext = {
                    events += "conversation.create"
                    throw createError
                },
                closeEngine = { events += "engine.close" },
                onEngineReleaseFailure = { throw AssertionError("unexpected engine release failure") }
            )
            throw AssertionError("Expected reset to fail")
        } catch (error: IllegalStateException) {
            error
        }

        assertSame(createError, thrown.cause)
        assertEquals(
            listOf("conversation.close", "conversation.create", "engine.close"),
            events
        )
    }
    @Test
    fun marksProcessUnavailableWhenEngineCloseThrowsNativeError() {
        val conversationCloseError = IllegalStateException("conversation close failed")
        val engineCloseError = UnsatisfiedLinkError("native engine close failed")
        val processHealth = LocalAiProcessHealth()

        val thrown = org.junit.Assert.assertThrows(IllegalStateException::class.java) {
            ConversationResetPolicy.recreateConversation(
                closePrevious = { throw conversationCloseError },
                createNext = { "must-not-be-created" },
                closeEngine = { throw engineCloseError },
                onEngineReleaseFailure = processHealth::markReleaseFailure
            )
        }

        assertSame(conversationCloseError, thrown.cause)
        assertEquals(listOf(engineCloseError), conversationCloseError.suppressed.toList())
        assertSame(engineCloseError, processHealth.releaseFailure())
        assertFalse(processHealth.isAvailable())
    }

}
