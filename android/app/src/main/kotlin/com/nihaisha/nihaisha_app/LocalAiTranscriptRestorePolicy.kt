package com.nihaisha.nihaisha_app

/**
 * Bounds history restoration without silently discarding the newest message.
 * The transcript cap is measured in UTF-16 code units, matching Kotlin String.
 */
internal data class LocalAiTranscriptRestorePayload(
    val completedTurns: List<*>,
    val omittedCompletedTurnCount: Int,
    val omittedCompletedCharacterCount: Long,
    val userMessages: List<String>,
    val userMessagesTruncated: Boolean
)

internal object LocalAiTranscriptRestorePolicy {
    const val maxTranscriptCharacters = 10_000
    const val maxUserMessages = 60
    const val userMessageSource = "用户文字自述"
    const val userMessageSourcePrefix = "用户文字自述："

    /**
     * Parse the required MethodChannel envelope without defaulting missing
     * fields. A missing list or count must never be treated as an empty history.
     */
    fun parsePayload(
        rawCompletedTurns: Any?,
        rawOmittedCompletedTurnCount: Any?,
        rawOmittedCompletedCharacterCount: Any?,
        rawUserMessages: Any?,
        rawUserMessagesTruncated: Any?
    ): LocalAiTranscriptRestorePayload {
        val completedTurns = rawCompletedTurns as? List<*>
            ?: throw IllegalArgumentException("completed_turns is required and must be a list")
        val omittedTurnCount = requiredNonNegativeInteger(
            rawOmittedCompletedTurnCount,
            "omitted_completed_turn_count",
            Int.MAX_VALUE.toLong()
        ).toInt()
        val omittedCharacterCount = requiredNonNegativeInteger(
            rawOmittedCompletedCharacterCount,
            "omitted_completed_character_count"
        )
        val rawMessages = rawUserMessages as? List<*>
            ?: throw IllegalArgumentException("userMessages is required and must be a list")
        require(rawMessages.size <= maxUserMessages) {
            "userMessages exceeds the bounded Native restore entry limit"
        }
        val userMessagesTruncated = rawUserMessagesTruncated as? Boolean
            ?: throw IllegalArgumentException(
                "user_messages_truncated is required and must be a boolean"
            )
        var formattedUserMessageCharacters = 0L
        val userMessages = rawMessages.mapIndexed { index, value ->
            val message = value as? String
                ?: throw IllegalArgumentException("userMessages[$index] must be a string")
            require(message.isNotBlank() && message == message.trim()) {
                "userMessages[$index] must be a non-empty trimmed string"
            }
            val formattedLength = message.length.toLong() + userMessageSourcePrefix.length
            require(formattedLength <= UserReportedInputPolicy.MAX_ENTRY_CHARS) {
                "userMessages[$index] exceeds the formatted Native entry character limit"
            }
            formattedUserMessageCharacters += formattedLength
            require(formattedUserMessageCharacters <= UserReportedInputPolicy.MAX_TOTAL_CHARS) {
                "userMessages exceeds the formatted Native aggregate character limit"
            }
            message
        }
        return LocalAiTranscriptRestorePayload(
            completedTurns = completedTurns,
            omittedCompletedTurnCount = omittedTurnCount,
            omittedCompletedCharacterCount = omittedCharacterCount,
            userMessages = userMessages,
            userMessagesTruncated = userMessagesTruncated
        )
    }

    private fun requiredNonNegativeInteger(
        value: Any?,
        field: String,
        maximum: Long = Long.MAX_VALUE
    ): Long {
        val number = when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> throw IllegalArgumentException("$field is required and must be an integer")
        }
        require(number >= 0L && number <= maximum) {
            "$field is outside the supported non-negative integer range"
        }
        return number
    }

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
