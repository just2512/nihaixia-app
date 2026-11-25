package com.nihaisha.nihaisha_app

import java.util.Collections

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
 * Bounded snapshot of the successful Native conversation transcript.
 *
 * [omittedCharacterCount] counts UTF-16 code units from whole turns that were
 * omitted. It is a transcript-size measure, not a model-token estimate.
 * [successfulTurnCount] survives eviction so a long-running conversation is
 * never misclassified as a first turn by GPU fallback policy.
 */
internal data class LocalAiConversationHistorySnapshot(
    val turns: List<LocalAiCompletedTurn>,
    val omittedTurnCount: Int,
    val omittedCharacterCount: Long,
    val successfulTurnCount: Long
)

/**
 * Owns the in-memory Native recovery transcript and bounds it independently
 * from the complete Flutter/SQLite conversation history.
 *
 * The retained Native transcript is limited by both complete-turn count and
 * UTF-16 code units. Eviction always removes whole oldest turns; no message is
 * cut mid-sentence or mid-surrogate pair. Omission counters are metadata only
 * and do not retain the removed message contents.
 */
internal class LocalAiConversationHistory(
    private val maxRetainedTurns: Int = LocalAiConversationHistoryPolicy.maxRetainedTurns,
    private val maxRetainedCharacters: Int = LocalAiConversationHistoryPolicy.maxRetainedCharacters
) {
    private val turns = mutableListOf<LocalAiCompletedTurn>()
    private var omittedTurnCount = 0
    private var omittedCharacterCount = 0L
    private var successfulTurnCount = 0L

    init {
        require(maxRetainedTurns > 0) { "maxRetainedTurns must be positive" }
        require(maxRetainedCharacters > 0) { "maxRetainedCharacters must be positive" }
    }

    fun appendSuccessfulTurn(userText: String, modelText: String) {
        require(userText.isNotBlank()) {
            "A blank user message cannot be recorded as a conversation turn"
        }
        require(modelText.isNotBlank()) {
            "A blank model response is not a successful conversation turn"
        }

        successfulTurnCount += 1L
        turns.add(LocalAiCompletedTurn(userText, modelText))
        while (
            turns.size > maxRetainedTurns ||
            retainedCharacterCount() > maxRetainedCharacters
        ) {
            val removed = turns.removeAt(0)
            omittedTurnCount += 1
            omittedCharacterCount += characterCount(removed)
        }
    }

    fun snapshot(): LocalAiConversationHistorySnapshot =
        LocalAiConversationHistorySnapshot(
            turns = Collections.unmodifiableList(ArrayList(turns)),
            omittedTurnCount = omittedTurnCount,
            omittedCharacterCount = omittedCharacterCount,
            successfulTurnCount = successfulTurnCount
        )

    fun restore(snapshot: LocalAiConversationHistorySnapshot) {
        require(snapshot.omittedTurnCount >= 0) { "omittedTurnCount cannot be negative" }
        require(snapshot.omittedCharacterCount >= 0L) {
            "omittedCharacterCount cannot be negative"
        }
        require(
            snapshot.successfulTurnCount ==
                snapshot.omittedTurnCount.toLong() + snapshot.turns.size.toLong()
        ) {
            "successfulTurnCount must equal retained plus omitted completed turns"
        }
        require(snapshot.turns.size <= maxRetainedTurns) {
            "Snapshot contains more turns than the configured limit"
        }
        require(snapshot.turns.sumOf(::characterCount) <= maxRetainedCharacters.toLong()) {
            "Snapshot exceeds the configured character limit"
        }

        turns.clear()
        turns.addAll(snapshot.turns)
        omittedTurnCount = snapshot.omittedTurnCount
        omittedCharacterCount = snapshot.omittedCharacterCount
        successfulTurnCount = snapshot.successfulTurnCount
    }

    fun clear() {
        turns.clear()
        omittedTurnCount = 0
        omittedCharacterCount = 0L
        successfulTurnCount = 0L
    }

    fun hasSuccessfulTurn(): Boolean = successfulTurnCount > 0L

    private fun retainedCharacterCount(): Long =
        turns.sumOf(::characterCount)

    private fun characterCount(turn: LocalAiCompletedTurn): Long =
        turn.userText.length.toLong() + turn.modelText.length.toLong()
}

/**
 * Pure transcript and prompt policy. Deliberately contains no LiteRT-LM SDK
 * types so its unit tests can run on the repository's JDK 17 test runtime; the
 * pinned SDK includes Java 21 bytecode and is converted to Message objects
 * only in MainActivity when constructing ConversationConfig.
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
    /**
     * Engineering ceiling for Native recovery history. Character budget is in
     * UTF-16 code units and is not a proxy for LiteRT-LM token count.
     */
    const val maxRetainedTurns = 12
    const val maxRetainedCharacters = 10_000

    fun initialMessages(
        snapshot: LocalAiConversationHistorySnapshot
    ): List<LocalAiTranscriptMessage> =
        snapshot.turns.flatMap { turn ->
            listOf(
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, turn.userText),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, turn.modelText)
            )
        }

    /**
     * Explicitly tells the model that older complete turns are unavailable.
     * The full UI transcript remains owned by the existing Flutter/SQLite
     * history; this instruction only describes the bounded Native replay set.
     */
    fun systemInstruction(
        baseInstruction: String,
        snapshot: LocalAiConversationHistorySnapshot
    ): String {
        if (snapshot.omittedTurnCount == 0) return baseInstruction
        val boundary = buildString {
            appendLine("【Native 对话历史边界】")
            appendLine(
                "受本地恢复历史预算限制，较早的完整成功轮次已省略 " +
                    "${snapshot.omittedTurnCount} 轮（累计 ${snapshot.omittedCharacterCount} 个 UTF-16 code units）。"
            )
            append("只能依据当前提供的保留对话内容作答；不得假设或补造已省略轮次中的信息。")
        }
        return "$baseInstruction\n\n$boundary"
    }
}

/**
 * Binds the one in-memory LiteRT-LM Conversation to exactly one persisted
 * assistant conversation. Switching IDs must clear all native transcript and
 * symptom-input state before another session can send.
 */
internal object LocalAiConversationSessionPolicy {
    fun shouldReset(
        activeConversationId: Long?,
        requestedConversationId: Long,
        hasActiveConversationState: Boolean
    ): Boolean {
        require(requestedConversationId > 0L) {
            "A positive persisted conversation ID is required"
        }
        return when {
            activeConversationId == requestedConversationId -> false
            activeConversationId == null && !hasActiveConversationState -> false
            else -> true
        }
    }
}
