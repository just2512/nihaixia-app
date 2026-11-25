package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiConversationHistoryPolicyTest {
    @Test
    fun appendsUserAndModelMessagesInTurnOrder() {
        val history = LocalAiConversationHistory()

        history.appendSuccessfulTurn("first question", "first answer")
        history.appendSuccessfulTurn("second question", "second answer")

        val snapshot = history.snapshot()
        assertEquals(
            listOf(
                LocalAiCompletedTurn("first question", "first answer"),
                LocalAiCompletedTurn("second question", "second answer")
            ),
            snapshot.turns
        )
        assertEquals(
            listOf(
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "first question"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "first answer"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "second question"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "second answer")
            ),
            LocalAiConversationHistoryPolicy.initialMessages(snapshot)
        )
        assertTrue(history.hasSuccessfulTurn())
        assertEquals(2L, snapshot.successfulTurnCount)
    }

    @Test
    fun snapshotIsDetachedAndReadOnly() {
        val history = LocalAiConversationHistory()
        history.appendSuccessfulTurn("first question", "first answer")

        val snapshot = history.snapshot()
        history.appendSuccessfulTurn("second question", "second answer")

        assertEquals(1, snapshot.turns.size)
        assertEquals("first question", snapshot.turns.first().userText)
        assertEquals(2, history.snapshot().turns.size)
        assertThrows(UnsupportedOperationException::class.java) {
            (snapshot.turns as MutableList<LocalAiCompletedTurn>).clear()
        }
    }

    @Test
    fun blankResponseIsNotPersistedAsSuccessfulTurn() {
        val history = LocalAiConversationHistory()

        assertThrows(IllegalArgumentException::class.java) {
            history.appendSuccessfulTurn("question", "  ")
        }
        assertTrue(history.snapshot().turns.isEmpty())
        assertFalse(history.hasSuccessfulTurn())
    }

    @Test
    fun keepsRetrievedContextOutOfNativeRecoveryTranscript() {
        val userText = "请解释这条原文。"
        val retrievedContext = "RAG_PRIVATE_CONTEXT::经典原文摘录"
        val prepared = LocalAiMessageInputPolicy.prepare(userText, retrievedContext)

        assertTrue(prepared.modelInput.contains(retrievedContext))
        assertTrue(prepared.modelInput.contains(userText))
        assertEquals(userText, prepared.historyUserText)

        val history = LocalAiConversationHistory()
        history.appendSuccessfulTurn(prepared.historyUserText, "模型解释")
        val replayMessages =
            LocalAiConversationHistoryPolicy.initialMessages(history.snapshot())

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
        val history = LocalAiConversationHistory()

        assertThrows(IllegalArgumentException::class.java) {
            history.appendSuccessfulTurn(" ", "answer")
        }
        assertTrue(history.snapshot().turns.isEmpty())
        assertFalse(history.hasSuccessfulTurn())
    }

    @Test
    fun evictsOnlyOldestWholeTurnsWhenTurnLimitIsExceeded() {
        val history = LocalAiConversationHistory(
            maxRetainedTurns = 2,
            maxRetainedCharacters = 100
        )
        history.appendSuccessfulTurn("u1", "m1")
        history.appendSuccessfulTurn("u2", "m2")
        history.appendSuccessfulTurn("u3", "m3")

        val snapshot = history.snapshot()
        assertEquals(
            listOf(
                LocalAiCompletedTurn("u2", "m2"),
                LocalAiCompletedTurn("u3", "m3")
            ),
            snapshot.turns
        )
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(4L, snapshot.omittedCharacterCount)
        assertEquals(3L, snapshot.successfulTurnCount)
        assertTrue(history.hasSuccessfulTurn())
    }

    @Test
    fun enforcesUtf16CharacterBudgetWithoutCuttingACompletedTurn() {
        val history = LocalAiConversationHistory(
            maxRetainedTurns = 10,
            maxRetainedCharacters = 8
        )
        history.appendSuccessfulTurn("abc", "def")
        history.appendSuccessfulTurn("123", "456")

        val snapshot = history.snapshot()
        assertEquals(listOf(LocalAiCompletedTurn("123", "456")), snapshot.turns)
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(6L, snapshot.omittedCharacterCount)
        assertEquals(6, snapshot.turns.single().userText.length +
            snapshot.turns.single().modelText.length)
    }

    @Test
    fun omitsAnOversizedNewestTurnWholeAndKeepsSuccessStateForFallback() {
        val history = LocalAiConversationHistory(
            maxRetainedTurns = 10,
            maxRetainedCharacters = 8
        )
        history.appendSuccessfulTurn("1234567", "xx")

        val snapshot = history.snapshot()
        assertTrue(snapshot.turns.isEmpty())
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(9L, snapshot.omittedCharacterCount)
        assertEquals(1L, snapshot.successfulTurnCount)
        assertTrue(history.hasSuccessfulTurn())
        assertTrue(
            LocalAiConversationHistoryPolicy.systemInstruction("base", snapshot)
                .contains("已省略 1 轮")
        )
    }

    @Test
    fun omissionInstructionIsAbsentWhenNoTurnWasOmitted() {
        val history = LocalAiConversationHistory()
        history.appendSuccessfulTurn("question", "answer")

        assertEquals(
            "base",
            LocalAiConversationHistoryPolicy.systemInstruction("base", history.snapshot())
        )
    }

    @Test
    fun restoresBoundedHistoryAndOmissionMetadataAcrossBackendRecreation() {
        val original = LocalAiConversationHistory(maxRetainedTurns = 1, maxRetainedCharacters = 50)
        original.appendSuccessfulTurn("older", "answer one")
        original.appendSuccessfulTurn("newer", "answer two")

        val restored = LocalAiConversationHistory(maxRetainedTurns = 1, maxRetainedCharacters = 50)
        restored.restore(original.snapshot())

        val snapshot = restored.snapshot()
        assertEquals(listOf(LocalAiCompletedTurn("newer", "answer two")), snapshot.turns)
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(2L, snapshot.successfulTurnCount)
        assertTrue(restored.hasSuccessfulTurn())
    }

    @Test
    fun clearResetsTurnsOmissionAndSuccessfulTurnState() {
        val history = LocalAiConversationHistory(maxRetainedTurns = 1, maxRetainedCharacters = 20)
        history.appendSuccessfulTurn("first", "answer one")
        history.appendSuccessfulTurn("second", "answer two")

        history.clear()

        val snapshot = history.snapshot()
        assertTrue(snapshot.turns.isEmpty())
        assertEquals(0, snapshot.omittedTurnCount)
        assertEquals(0L, snapshot.omittedCharacterCount)
        assertEquals(0L, snapshot.successfulTurnCount)
        assertFalse(history.hasSuccessfulTurn())
    }
}
