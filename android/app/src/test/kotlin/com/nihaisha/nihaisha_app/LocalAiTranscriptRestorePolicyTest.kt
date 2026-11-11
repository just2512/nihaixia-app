package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun longTranscriptKeepsMarkerAndNewestTailWithinLimit() {
        val newest = "最新一轮的完整结尾"
        val transcript = "较早历史".repeat(2_000) + newest

        val bounded = LocalAiTranscriptRestorePolicy.boundTranscript(transcript)

        assertTrue(bounded.startsWith(marker))
        assertTrue(bounded.endsWith(newest))
        assertTrue(bounded.length <= LocalAiTranscriptRestorePolicy.maxTranscriptCharacters)
    }

    @Test
    fun alreadyMarkedTranscriptRetainsMarkerAndNewestTail() {
        val newest = "最近一条助手回复"
        val transcript = marker + "较早历史".repeat(2_000) + newest

        val bounded = LocalAiTranscriptRestorePolicy.boundTranscript(transcript)

        assertTrue(bounded.startsWith(marker))
        assertTrue(bounded.endsWith(newest))
        assertTrue(bounded.length <= LocalAiTranscriptRestorePolicy.maxTranscriptCharacters)
    }

    @Test
    fun truncationDoesNotStartWithAnUnpairedLowSurrogate() {
        val transcript = "a".repeat(9_999) + "😀" + "最新"
        val bounded = LocalAiTranscriptRestorePolicy.boundTranscript(transcript)
        val bodyStart = bounded.length - ("😀最新".length)

        assertTrue(bounded.length <= LocalAiTranscriptRestorePolicy.maxTranscriptCharacters)
        assertFalse(Character.isLowSurrogate(bounded[marker.length]))
        assertTrue(bounded.endsWith("😀最新"))
        assertTrue(bodyStart >= 0)
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
