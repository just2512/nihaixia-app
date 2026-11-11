package com.nihaisha.nihaisha_app

/**
 * Bounds history restoration without silently discarding the newest message.
 * The transcript cap is measured in UTF-16 code units, matching Kotlin String.
 */
internal object LocalAiTranscriptRestorePolicy {
    const val maxTranscriptCharacters = 10_000
    const val maxUserMessages = 60
    private const val truncationMarker = "【较早历史已省略，以下为最近内容】\n"

    fun boundTranscript(transcript: String): String {
        if (transcript.length <= maxTranscriptCharacters) return transcript

        val alreadyMarked = transcript.startsWith(truncationMarker)
        val body = if (alreadyMarked) transcript.removePrefix(truncationMarker) else transcript
        val marker = if (alreadyMarked) "" else truncationMarker
        val availableBodyCharacters = maxTranscriptCharacters - marker.length
        return marker + suffixWithoutSplittingSurrogate(body, availableBodyCharacters)
    }

    fun recentUserMessages(messages: List<String>): List<String> =
        messages.takeLast(maxUserMessages)

    fun hasOmittedUserMessages(messages: List<String>): Boolean =
        messages.size > maxUserMessages

    private fun suffixWithoutSplittingSurrogate(value: String, maxCharacters: Int): String {
        if (maxCharacters <= 0) return ""
        var start = (value.length - maxCharacters).coerceAtLeast(0)
        if (start > 0 && start < value.length && Character.isLowSurrogate(value[start])) {
            start += 1
        }
        return value.substring(start)
    }
}
