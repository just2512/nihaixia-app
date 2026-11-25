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
        require(transcript.length <= maxTranscriptCharacters) {
            "Transcript must be bounded at complete-turn boundaries before Native restore"
        }
        require(!hasUnpairedSurrogate(transcript)) {
            "Transcript contains an unpaired UTF-16 surrogate"
        }
        return transcript
    }

    fun recentUserMessages(messages: List<String>): List<String> =
        messages.takeLast(maxUserMessages)

    fun hasOmittedUserMessages(messages: List<String>): Boolean =
        messages.size > maxUserMessages

    private fun hasUnpairedSurrogate(value: String): Boolean {
        var index = 0
        while (index < value.length) {
            val current = value[index]
            when {
                Character.isHighSurrogate(current) -> {
                    if (index + 1 >= value.length ||
                        !Character.isLowSurrogate(value[index + 1])
                    ) return true
                    index += 2
                }
                Character.isLowSurrogate(current) -> return true
                else -> index += 1
            }
        }
        return false
    }
}
