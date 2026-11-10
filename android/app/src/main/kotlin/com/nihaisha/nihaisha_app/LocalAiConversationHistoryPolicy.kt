package com.nihaisha.nihaisha_app

import com.google.ai.edge.litertlm.Message

/**
 * Stores only completed user/model exchanges for ConversationConfig.initialMessages.
 * The in-flight request is appended only after a non-blank model response.
 */
internal object LocalAiConversationHistoryPolicy {
    fun appendSuccessfulTurn(
        history: MutableList<Message>,
        userMessage: Message,
        assistantText: String
    ) {
        require(assistantText.isNotBlank()) {
            "A blank model response is not a successful conversation turn"
        }
        history.add(userMessage)
        history.add(Message.model(assistantText))
    }

    fun snapshot(history: List<Message>): List<Message> = history.toList()
}
