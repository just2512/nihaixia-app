package com.nihaisha.nihaisha_app

import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.Role
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiConversationHistoryPolicyTest {
    @Test
    fun appendsUserAndModelMessagesInTurnOrder() {
        val history = mutableListOf<Message>()

        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            Message.user("first question"),
            "first answer"
        )
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            Message.user("second question"),
            "second answer"
        )

        assertEquals(
            listOf(Role.USER, Role.MODEL, Role.USER, Role.MODEL),
            history.map { it.role }
        )
        assertEquals(
            listOf("first question", "first answer", "second question", "second answer"),
            history.map { it.contents.toString() }
        )
    }

    @Test
    fun snapshotPreservesOrderAndDoesNotTrackLaterMutations() {
        val history = mutableListOf<Message>()
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            Message.user("first question"),
            "first answer"
        )

        val snapshot = LocalAiConversationHistoryPolicy.snapshot(history)
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            Message.user("second question"),
            "second answer"
        )

        assertEquals(2, snapshot.size)
        assertEquals("first question", snapshot.first().contents.toString())
        assertEquals(4, history.size)
    }

    @Test
    fun blankResponseIsNotPersistedAsSuccessfulTurn() {
        val history = mutableListOf<Message>()

        assertThrows(IllegalArgumentException::class.java) {
            LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
                history,
                Message.user("question"),
                "  "
            )
        }
        assertTrue(history.isEmpty())
    }
}
