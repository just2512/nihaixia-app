package com.nihaisha.nihaisha_app

/**
 * Bounds the user-only transcript copied into the temporary symptom-extraction
 * conversation. Limits are measured in UTF-16 code units, not model tokens.
 */
internal object UserReportedInputPolicy {
    const val MAX_ENTRIES = 100
    const val MAX_ENTRY_CHARS = 2_000
    const val MAX_TOTAL_CHARS = 16_000

    data class AppendResult(
        val entries: List<String>,
        val truncated: Boolean
    )

    fun append(
        currentEntries: List<String>,
        newEntry: String,
        wasTruncated: Boolean = false
    ): AppendResult {
        val normalized = newEntry.trim()
        if (normalized.isEmpty()) {
            return AppendResult(currentEntries.toList(), wasTruncated)
        }

        val boundedEntry = truncateWithoutSplittingSurrogatePair(
            normalized,
            MAX_ENTRY_CHARS
        )
        val nextEntries = currentEntries.toMutableList()
        nextEntries.add(boundedEntry)

        var truncated = wasTruncated || normalized.length > MAX_ENTRY_CHARS
        var totalChars = nextEntries.sumOf { it.length }
        while (nextEntries.size > MAX_ENTRIES || totalChars > MAX_TOTAL_CHARS) {
            totalChars -= nextEntries.removeAt(0).length
            truncated = true
        }

        return AppendResult(nextEntries.toList(), truncated)
    }

    private fun truncateWithoutSplittingSurrogatePair(
        value: String,
        maxChars: Int
    ): String {
        if (value.length <= maxChars) return value
        var end = maxChars
        if (end > 0 &&
            end < value.length &&
            Character.isHighSurrogate(value[end - 1]) &&
            Character.isLowSurrogate(value[end])
        ) {
            end -= 1
        }
        return value.substring(0, end)
    }
}