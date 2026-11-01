package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UserReportedInputPolicyTest {
    @Test
    fun keepsShortEntriesInChronologicalOrder() {
        val first = UserReportedInputPolicy.append(emptyList(), "用户文字自述：先出现的症状")
        val second = UserReportedInputPolicy.append(
            first.entries,
            "语音识别草稿：后出现的症状",
            first.truncated
        )

        assertEquals(
            listOf("用户文字自述：先出现的症状", "语音识别草稿：后出现的症状"),
            second.entries
        )
        assertFalse(second.truncated)
    }

    @Test
    fun truncatesAnOversizedEntryAndMarksTheSnapshot() {
        val result = UserReportedInputPolicy.append(
            emptyList(),
            "x".repeat(UserReportedInputPolicy.MAX_ENTRY_CHARS + 1)
        )

        assertEquals(1, result.entries.size)
        assertEquals(UserReportedInputPolicy.MAX_ENTRY_CHARS, result.entries.single().length)
        assertTrue(result.truncated)
    }

    @Test
    fun doesNotSplitASurrogatePairAtTheEntryLimit() {
        val result = UserReportedInputPolicy.append(
            emptyList(),
            "x".repeat(UserReportedInputPolicy.MAX_ENTRY_CHARS - 1) + "🙂"
        )

        assertEquals(UserReportedInputPolicy.MAX_ENTRY_CHARS - 1, result.entries.single().length)
        assertFalse(Character.isHighSurrogate(result.entries.single().last()))
        assertTrue(result.truncated)
    }

    @Test
    fun removesOldestEntriesWhenTotalCharacterLimitIsExceeded() {
        val first = "a".repeat(8_000)
        val second = "b".repeat(8_000)
        val result = UserReportedInputPolicy.append(listOf(first, second), "c")

        assertEquals(listOf(second, "c"), result.entries)
        assertEquals(8_001, result.entries.sumOf { it.length })
        assertTrue(result.truncated)
    }

    @Test
    fun enforcesTheEntryCountLimitEvenForShortEntries() {
        val current = List(UserReportedInputPolicy.MAX_ENTRIES) { "old-$it" }
        val result = UserReportedInputPolicy.append(current, "new-entry")

        assertEquals(UserReportedInputPolicy.MAX_ENTRIES, result.entries.size)
        assertEquals("old-1", result.entries.first())
        assertEquals("new-entry", result.entries.last())
        assertTrue(result.truncated)
    }

    @Test
    fun preservesTruncationNoticeAndIgnoresBlankInput() {
        val existing = listOf("此前已发生截断")
        val result = UserReportedInputPolicy.append(
            currentEntries = existing,
            newEntry = "   ",
            wasTruncated = true
        )

        assertEquals(existing, result.entries)
        assertTrue(result.truncated)
    }
}