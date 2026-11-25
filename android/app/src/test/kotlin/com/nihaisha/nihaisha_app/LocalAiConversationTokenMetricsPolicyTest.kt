package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiConversationTokenMetricsPolicyTest {
    @Test
    fun reportsMeasuredValuesOnlyWhenBothSourcesAreKnown() {
        val snapshot = LocalAiConversationTokenMetricsPolicy.snapshot(
            conversationTokenCount = 4_321,
            modelMaxContextTokens = 32_768
        )

        assertEquals(LocalAiConversationTokenMetricsStatus.MEASURED, snapshot.status)
        assertEquals(4_321, snapshot.conversationTokenCount)
        assertEquals(32_768, snapshot.modelMaxContextTokens)
        assertEquals(
            mapOf(
                "status" to "MEASURED",
                "unit" to "KV_CACHE_TOKENS",
                "conversationTokenCount" to 4_321,
                "modelMaxContextTokens" to 32_768
            ),
            snapshot.toMethodChannelMap()
        )
    }

    @Test
    fun reportsConversationCountWhenModelLimitIsUnknown() {
        val snapshot = LocalAiConversationTokenMetricsPolicy.snapshot(
            conversationTokenCount = 123,
            modelMaxContextTokens = null
        )

        assertEquals(LocalAiConversationTokenMetricsStatus.TOKEN_COUNT_ONLY, snapshot.status)
        assertEquals(123, snapshot.conversationTokenCount)
        assertEquals(null, snapshot.modelMaxContextTokens)
        assertFalse(snapshot.toMethodChannelMap().containsKey("modelMaxContextTokens"))
    }

    @Test
    fun reportsModelLimitWhenConversationIsNotAvailable() {
        val snapshot = LocalAiConversationTokenMetricsPolicy.snapshot(
            conversationTokenCount = null,
            modelMaxContextTokens = 8_192
        )

        assertEquals(LocalAiConversationTokenMetricsStatus.MODEL_LIMIT_ONLY, snapshot.status)
        assertEquals(null, snapshot.conversationTokenCount)
        assertEquals(8_192, snapshot.modelMaxContextTokens)
        assertFalse(snapshot.toMethodChannelMap().containsKey("conversationTokenCount"))
    }

    @Test
    fun rejectsInvalidNegativeOrZeroMetadataAsUnknown() {
        val snapshot = LocalAiConversationTokenMetricsPolicy.snapshot(
            conversationTokenCount = -1,
            modelMaxContextTokens = 0
        )

        assertEquals(LocalAiConversationTokenMetricsStatus.UNKNOWN, snapshot.status)
        assertEquals(null, snapshot.conversationTokenCount)
        assertEquals(null, snapshot.modelMaxContextTokens)
        assertEquals("UNKNOWN", snapshot.toMethodChannelMap()["status"])
    }

    @Test
    fun zeroCurrentTokenCountIsAValidObservation() {
        val snapshot = LocalAiConversationTokenMetricsPolicy.snapshot(
            conversationTokenCount = 0,
            modelMaxContextTokens = 16_384
        )

        assertEquals(LocalAiConversationTokenMetricsStatus.MEASURED, snapshot.status)
        assertEquals(0, snapshot.conversationTokenCount)
        assertTrue(snapshot.toMethodChannelMap().containsKey("conversationTokenCount"))
    }
}
