package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiTranscriptRestorePolicyTest {
    private val marker = "【较早历史已省略，以下为最近内容】\n"

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
            LocalAiTranscriptRestorePolicy.boundTranscript("文本\\uD83D")
        }

        assertTrue(error.message!!.contains("unpaired UTF-16 surrogate"))
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
