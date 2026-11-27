package com.nihaisha.nihaisha_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiTranscriptRestorePolicyTest {

    @Test
    fun preservesShortTranscriptExactly() {
        val transcript = "用户：第一条\n助手：第一答"
        assertEquals(transcript, LocalAiTranscriptRestorePolicy.boundTranscript(transcript))
    }

    @Test
    fun rejectsOversizedTranscriptInsteadOfCuttingThroughAMessage() {
        val transcript = "较早历史".repeat(4_000) + "最新一轮的完整结尾"

        val error = org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            LocalAiTranscriptRestorePolicy.boundTranscript(transcript)
        }

        assertTrue(error.message!!.contains("complete-turn boundaries"))
    }

    @Test
    fun acceptsExactlyBoundedTranscriptWithoutChangingIt() {
        val transcript = "😀".repeat(
            LocalAiTranscriptRestorePolicy.maxTranscriptCharacters / 2
        )

        assertEquals(
            LocalAiTranscriptRestorePolicy.maxTranscriptCharacters,
            transcript.length
        )
        assertEquals(transcript, LocalAiTranscriptRestorePolicy.boundTranscript(transcript))
    }

    @Test
    fun rejectsUnpairedUtf16SurrogatesAtNativeBoundary() {
        val error = org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            LocalAiTranscriptRestorePolicy.boundTranscript("文本" + Char(0xD83D))
        }

        assertTrue(error.message!!.contains("unpaired UTF-16 surrogate"))
    }

    @Test
    fun restoresTypedCompletedTurnsWithoutFlatteningTheirRoles() {
        val snapshot = LocalAiTranscriptRestorePolicy.historySnapshot(
            rawTurns = listOf(
                mapOf("user_text" to "第一问", "assistant_text" to "第一答"),
                mapOf("user_text" to "第二问", "assistant_text" to "第二答")
            ),
            omittedCompletedTurnCount = 3,
            omittedCompletedCharacterCount = 120L
        )

        assertEquals(
            listOf(
                LocalAiCompletedTurn("第一问", "第一答"),
                LocalAiCompletedTurn("第二问", "第二答")
            ),
            snapshot.turns
        )
        assertEquals(3, snapshot.omittedTurnCount)
        assertEquals(120L, snapshot.omittedCharacterCount)
        assertEquals(5L, snapshot.successfulTurnCount)
        assertEquals(
            listOf(
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "第一问"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "第一答"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "第二问"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "第二答")
            ),
            LocalAiConversationHistoryPolicy.initialMessages(snapshot)
        )
    }

    @Test
    fun rejectsInvalidStructuredTurnsAndNativeBudgetOverflow() {
        val missingRole = org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            LocalAiTranscriptRestorePolicy.historySnapshot(
                rawTurns = listOf(mapOf("user_text" to "问题")),
                omittedCompletedTurnCount = 0,
                omittedCompletedCharacterCount = 0L
            )
        }
        assertTrue(missingRole.message!!.contains("assistant_text"))

        val oversized = org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            LocalAiTranscriptRestorePolicy.historySnapshot(
                rawTurns = listOf(
                    mapOf("user_text" to "U".repeat(10_000), "assistant_text" to "答")
                ),
                omittedCompletedTurnCount = 0,
                omittedCompletedCharacterCount = 0L
            )
        }
        assertTrue(oversized.message!!.contains("character limit"))

        val invalidSurrogate = org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            LocalAiTranscriptRestorePolicy.historySnapshot(
                rawTurns = listOf(
                    mapOf("user_text" to "问题" + Char(0xD83D), "assistant_text" to "回答")
                ),
                omittedCompletedTurnCount = 0,
                omittedCompletedCharacterCount = 0L
            )
        }
        assertTrue(invalidSurrogate.message!!.contains("surrogate"))
    }

    @Test
    fun keepsOnlyMostRecentSixtyUserMessages() {
        val messages = (1..75).map { "user-$it" }

        assertEquals("user-16", LocalAiTranscriptRestorePolicy.recentUserMessages(messages).first())
        assertEquals("user-75", LocalAiTranscriptRestorePolicy.recentUserMessages(messages).last())
        assertEquals(60, LocalAiTranscriptRestorePolicy.recentUserMessages(messages).size)
    }

    @Test
    fun marksUserMessageHistoryIncompleteOnlyWhenOlderMessagesWereOmitted() {
        assertFalse(LocalAiTranscriptRestorePolicy.hasOmittedUserMessages((1..60).map { "$it" }))
        assertTrue(LocalAiTranscriptRestorePolicy.hasOmittedUserMessages((1..61).map { "$it" }))
    }
}
