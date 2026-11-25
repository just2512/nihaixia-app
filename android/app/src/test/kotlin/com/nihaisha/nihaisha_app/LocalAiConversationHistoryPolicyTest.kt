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
    fun keepsRetrievedContextOutOfNativeRecoveryTranscript() {
        val userText = "请解释这条原文。"
        val retrievedContext = "RAG_PRIVATE_CONTEXT::经典原文摘录"

        val prepared = LocalAiMessageInputPolicy.prepare(userText, retrievedContext)

        assertTrue(prepared.modelInput.contains(retrievedContext))
        assertTrue(prepared.modelInput.contains(userText))
        assertEquals(userText, prepared.historyUserText)

        val history = mutableListOf<LocalAiCompletedTurn>()
        LocalAiConversationHistoryPolicy.appendSuccessfulTurn(
            history,
            prepared.historyUserText,
            "模型解释"
        )
        val replayMessages = LocalAiConversationHistoryPolicy.initialMessages(history)

        assertEquals(LocalAiTranscriptRole.USER, replayMessages[0].role)
        assertEquals(userText, replayMessages[0].text)
        assertTrue(replayMessages.none { it.text.contains(retrievedContext) })
    }

    @Test
    fun preservesPlainUserTextWhenNoRetrievedContextExists() {
        val userText = "你好"
        val prepared = LocalAiMessageInputPolicy.prepare(userText, "")

        assertEquals(userText, prepared.modelInput)
        assertEquals(userText, prepared.historyUserText)
    }

    @Test
    fun bindsFreshEmptyNativeConversationWithoutReset() {
        assertTrue(!LocalAiConversationSessionPolicy.shouldReset(null, 11L, false))
    }

    @Test
    fun preservesHistoryForTheSameConversationId() {
        assertTrue(!LocalAiConversationSessionPolicy.shouldReset(11L, 11L, true))
    }

    @Test
    fun resetsNativeStateWhenSwitchingConversationIds() {
        assertTrue(LocalAiConversationSessionPolicy.shouldReset(11L, 12L, true))
    }

    @Test
    fun resetsUnboundNativeStateWhenItAlreadyContainsConversationData() {
        assertTrue(LocalAiConversationSessionPolicy.shouldReset(null, 12L, true))
    }

    @Test
    fun rejectsMissingOrInvalidConversationIds() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiConversationSessionPolicy.shouldReset(null, 0L, false)
        }
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
