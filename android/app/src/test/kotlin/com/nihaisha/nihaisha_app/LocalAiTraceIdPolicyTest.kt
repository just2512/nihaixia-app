package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class LocalAiTraceIdPolicyTest {
    @Test
    fun absentTraceIdPreservesLegacyResponse() {
        assertNull(LocalAiTraceIdPolicy.normalize(null))
        val payload = mapOf("reply" to "ok")
        assertEquals(payload, LocalAiTraceIdPolicy.attach(payload, null))
    }

    @Test
    fun validTraceIdIsNormalizedAndEchoedAsMetadata() {
        val traceId = "0123456789abcdef0123456789abcdef"
        assertEquals(traceId, LocalAiTraceIdPolicy.normalize(" $traceId "))
        assertEquals(
            mapOf("reply" to "ok", "traceId" to traceId),
            LocalAiTraceIdPolicy.attach(mapOf("reply" to "ok"), traceId)
        )
    }

    @Test
    fun malformedTraceIdIsRejected() {
        try {
            LocalAiTraceIdPolicy.normalize("user text must never be a trace ID")
            fail("Expected malformed trace ID to be rejected")
        } catch (_: IllegalArgumentException) {
            // Expected: trace IDs are fixed-length opaque hexadecimal metadata.
        }
    }
}
