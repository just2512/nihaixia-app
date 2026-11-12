package com.nihaisha.nihaisha_app

internal object LocalAiTraceIdPolicy {
    private val traceIdPattern = Regex("^[0-9a-f]{32}$")

    fun normalize(raw: String?): String? {
        if (raw == null) return null
        val normalized = raw.trim()
        require(traceIdPattern.matches(normalized)) {
            "TRACE ID must be 32 lowercase hexadecimal characters"
        }
        return normalized
    }

    fun attach(
        payload: Map<String, Any>,
        traceId: String?
    ): Map<String, Any> {
        if (traceId == null) return payload
        return payload + ("trace_id" to traceId)
    }
}
