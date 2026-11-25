package com.nihaisha.nihaisha_app

internal enum class LocalAiTranscriptRole {
    USER,
    MODEL
}

internal data class LocalAiCompletedTurn(
    val userText: String,
    val modelText: String
)

internal data class LocalAiTranscriptMessage(
    val role: LocalAiTranscriptRole,
    val text: String
)

/**
 * Pure transcript policy. Deliberately contains no LiteRT-LM SDK types so its
 * unit tests can run on the repository's JDK 17 test runtime; the pinned SDK
 * includes Java 21 bytecode and is converted to Message objects only in
 * MainActivity when constructing ConversationConfig.
 */
internal data class LocalAiPreparedMessage(
    val modelInput: String,
    val historyUserText: String
)

/**
 * Separates the current-turn prompt payload from the clean user text retained
 * for Native Conversation recovery. Retrieved context is ephemeral and must
 * never be serialized into the completed-turn transcript.
 */
internal object LocalAiMessageInputPolicy {
    fun prepare(userText: String, context: String): LocalAiPreparedMessage {
        val modelInput = if (context.isBlank()) userText else buildString {
            appendLine("【应用提供的角色说明与本地检索资料】")
            appendLine(context.take(7000))
            appendLine("【用户原文】")
            append(userText)
        }
        return LocalAiPreparedMessage(
            modelInput = modelInput,
            historyUserText = userText
        )
    }
}

internal object LocalAiConversationHistoryPolicy {
    fun appendSuccessfulTurn(
        history: MutableList<LocalAiCompletedTurn>,
        userText: String,
        modelText: String
    ) {
        require(userText.isNotBlank()) {
            "A blank user message cannot be recorded as a conversation turn"
        }
        require(modelText.isNotBlank()) {
            "A blank model response is not a successful conversation turn"
        }
        history.add(LocalAiCompletedTurn(userText, modelText))
    }

    fun snapshot(history: List<LocalAiCompletedTurn>): List<LocalAiCompletedTurn> =
        history.toList()

    fun initialMessages(
        history: List<LocalAiCompletedTurn>
    ): List<LocalAiTranscriptMessage> =
        snapshot(history).flatMap { turn ->
            listOf(
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, turn.userText),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, turn.modelText)
            )
        }
}
