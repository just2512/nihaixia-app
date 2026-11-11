package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiConversationHistoryPolicyTest {
    @Test
    fun appendsUserAndModelMessagesInTurnOrder() {
        val history = mutableListOf<LocalAiCompletedTurn>()

        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            "first question",
            "first answer"
        )
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            "second question",
            "second answer"
        )

        assertEquals(
            listOf(
                LocalAiCompletedTurn("first question", "first answer"),
                LocalAiCompletedTurn("second question", "second answer")
            ),
            history
        )
        assertEquals(
            listOf(
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "first question"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "first answer"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "second question"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "second answer")
            ),
            LocalAiConversationHistoryPolicy.initialMessages(history)
        )
    }

    @Test
    fun snapshotPreservesOrderAndDoesNotTrackLaterMutations() {
        val history = mutableListOf<LocalAiCompletedTurn>()
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            "first question",
            "first answer"
        )

        val snapshot = LocalAiConversationHistoryPolicy.snapshot(history)
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            "second question",
            "second answer"
        )

        assertEquals(1, snapshot.size)
        assertEquals("first question", snapshot.first().userText)
        assertEquals(2, history.size)
    }

    @Test
    fun blankResponseIsNotPersistedAsSuccessfulTurn() {
        val history = mutableListOf<LocalAiCompletedTurn>()

        assertThrows(IllegalArgumentException::class.java) {
            LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
                history,
                "question",
                "  "
            )
        }
        assertTrue(history.isEmpty())
    }

    @Test
    fun blankUserInputIsRejected() {
        val history = mutableListOf<LocalAiCompletedTurn>()

        assertThrows(IllegalArgumentException::class.java) {
            LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
                history,
                " ",
                "answer"
            )
        }
        assertTrue(history.isEmpty())
    }
}
