package com.nihaisha.nihaisha_app

/**
 * Bounds history restoration without silently discarding the newest message.
 * The transcript cap is measured in UTF-16 code units, matching Kotlin String.
 */
internal object LocalAiTranscriptRestorePolicy {
    const val maxTranscriptCharacters = 10_000
    const val maxUserMessages = 60

    fun boundTranscript(transcript: String): String {
        require(transcript.length <= maxTranscriptCharacters) {
            "Transcript must be bounded at complete-turn boundaries before Native restore"
        }
        require(!hasUnpairedSurrogate(transcript)) {
            "Transcript contains an unpaired UTF-16 surrogate"
        }
        return transcript
    }

    fun historySnapshot(
        rawTurns: List<*>,
        omittedCompletedTurnCount: Int,
        omittedCompletedCharacterCount: Long
    ): LocalAiConversationHistorySnapshot {
        require(omittedCompletedTurnCount >= 0) {
            "omittedCompletedTurnCount cannot be negative"
        }
        require(omittedCompletedCharacterCount >= 0L) {
            "omittedCompletedCharacterCount cannot be negative"
        }
        require(rawTurns.size <= LocalAiConversationHistoryPolicy.maxRetainedTurns) {
            "Structured transcript exceeds the Native completed-turn limit"
        }
        val turns = rawTurns.mapIndexed { index, rawTurn ->
            val turn = rawTurn as? Map<*, *>
                ?: throw IllegalArgumentException("Completed turn $index is not a map")
            val userText = turn["user_text"] as? String
                ?: throw IllegalArgumentException("Completed turn $index has no user_text")
            val assistantText = turn["assistant_text"] as? String
                ?: throw IllegalArgumentException("Completed turn $index has no assistant_text")
            require(userText.isNotBlank()) { "Completed turn $index has blank user_text" }
            require(assistantText.isNotBlank()) { "Completed turn $index has blank assistant_text" }
            require(!hasUnpairedSurrogate(userText) && !hasUnpairedSurrogate(assistantText)) {
                "Completed turn $index contains an unpaired UTF-16 surrogate"
            }
            LocalAiCompletedTurn(userText, assistantText)
        }
        val retainedCharacters = turns.sumOf {
            it.userText.length.toLong() + it.modelText.length.toLong()
        }
        require(retainedCharacters <= LocalAiConversationHistoryPolicy.maxRetainedCharacters) {
            "Structured transcript exceeds the Native UTF-16 character limit"
        }
        return LocalAiConversationHistorySnapshot(
            turns = turns,
            omittedTurnCount = omittedCompletedTurnCount,
            omittedCharacterCount = omittedCompletedCharacterCount,
            successfulTurnCount = omittedCompletedTurnCount.toLong() + turns.size.toLong()
        )
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
