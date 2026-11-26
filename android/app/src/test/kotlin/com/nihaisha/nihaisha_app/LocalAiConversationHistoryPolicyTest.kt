package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiConversationHistoryPolicyTest {
    @Test
    fun appendsUserAndModelMessagesInTurnOrder() {
        val history = LocalAiConversationHistory()

        history.appendSuccessfulTurn("first question", "first answer")
        history.appendSuccessfulTurn("second question", "second answer")

        val snapshot = history.snapshot()
        assertEquals(
            listOf(
                LocalAiCompletedTurn("first question", "first answer"),
                LocalAiCompletedTurn("second question", "second answer")
            ),
            snapshot.turns
        )
        assertEquals(
            listOf(
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "first question"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "first answer"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.USER, "second question"),
                LocalAiTranscriptMessage(LocalAiTranscriptRole.MODEL, "second answer")
            ),
            LocalAiConversationHistoryPolicy.initialMessages(snapshot)
        )
        assertTrue(history.hasSuccessfulTurn())
        assertEquals(2L, snapshot.successfulTurnCount)
    }

    @Test
    fun snapshotIsDetachedAndReadOnly() {
        val history = LocalAiConversationHistory()
        history.appendSuccessfulTurn("first question", "first answer")

        val snapshot = history.snapshot()
        history.appendSuccessfulTurn("second question", "second answer")

        assertEquals(1, snapshot.turns.size)
        assertEquals("first question", snapshot.turns.first().userText)
        assertEquals(2, history.snapshot().turns.size)
        assertThrows(UnsupportedOperationException::class.java) {
            (snapshot.turns as MutableList<LocalAiCompletedTurn>).clear()
        }
    }

    @Test
    fun blankResponseIsNotPersistedAsSuccessfulTurn() {
        val history = LocalAiConversationHistory()

        assertThrows(IllegalArgumentException::class.java) {
            history.appendSuccessfulTurn("question", "  ")
        }
        assertTrue(history.snapshot().turns.isEmpty())
        assertFalse(history.hasSuccessfulTurn())
    }

    @Test
    fun rejectsRepeatedGreetingLoopsBeforeTheyCanEnterConversationHistory() {
        listOf(
            "您好您好您好您好",
            "您好。您好！您好，您好。",
            "您好\n您好\n您好\n您好"
        ).forEach { response ->
            assertEquals(
                "REPEATED_OUTPUT_LOOP",
                LocalAiGeneratedReplyQualityPolicy.rejectionReasonCode(response)
            )
            val history = LocalAiConversationHistory()
            assertThrows(IllegalArgumentException::class.java) {
                history.appendSuccessfulTurn("question", response)
            }
            assertTrue(history.snapshot().turns.isEmpty())
            assertFalse(history.hasSuccessfulTurn())
        }
    }

    @Test
    fun acceptsShortAndSubstantiveRepliesThatAreNotRepetitionLoops() {
        listOf(
            "您好",
            "您好，我可以介绍桔梗汤的组成和传统应用。",
            "第一点：桔梗。\n第二点：甘草。\n第三点：需要结合具体问题理解。"
        ).forEach { response ->
            assertEquals(
                null,
                LocalAiGeneratedReplyQualityPolicy.rejectionReasonCode(response)
            )
        }
    }

    @Test
    fun rejectsEmptyOutputAndKeepsTheHistoryUnchanged() {
        val history = LocalAiConversationHistory()
        assertEquals(
            "EMPTY_REPLY",
            LocalAiGeneratedReplyQualityPolicy.rejectionReasonCode("   ")
        )
        assertThrows(IllegalArgumentException::class.java) {
            history.appendSuccessfulTurn("question", "   ")
        }
        assertTrue(history.snapshot().turns.isEmpty())
        assertEquals(0L, history.snapshot().successfulTurnCount)
    }

    @Test
    fun keepsRetrievedContextOutOfNativeRecoveryTranscript() {
        val userText = "请解释这条原文。"
        val retrievedContext = "RAG_PRIVATE_CONTEXT::经典原文摘录"
        val sessionMemory = "SESSION_MEMORY_PRIVATE::USER_CONFIRMED"
        val prepared = LocalAiMessageInputPolicy.prepare(
            userText, retrievedContext, sessionMemory
        )

        assertTrue(prepared.modelInput.contains(retrievedContext))
        assertTrue(prepared.modelInput.contains(sessionMemory))
        assertTrue(prepared.modelInput.contains(userText))
        assertEquals(userText, prepared.historyUserText)

        val history = LocalAiConversationHistory()
        history.appendSuccessfulTurn(prepared.historyUserText, "模型解释")
        val replayMessages =
            LocalAiConversationHistoryPolicy.initialMessages(history.snapshot())

        assertEquals(LocalAiTranscriptRole.USER, replayMessages[0].role)
        assertEquals(userText, replayMessages[0].text)
        assertTrue(replayMessages.none { it.text.contains(retrievedContext) })
        assertTrue(replayMessages.none { it.text.contains(sessionMemory) })
    }

    @Test
    fun preservesPlainUserTextWhenNoRetrievedContextExists() {
        val userText = "你好"
        val prepared = LocalAiMessageInputPolicy.prepare(userText, "")

        assertEquals(userText, prepared.modelInput)
        assertEquals(userText, prepared.historyUserText)
    }


    @Test
    fun rebuildsBeforeNextTurnWhenLiveConversationContainsEphemeralContext() {
        assertTrue(
            LocalAiConversationEphemeralContextPolicy.shouldRebuildBeforeNextTurn(true)
        )
    }

    @Test
    fun doesNotRebuildBeforeNextTurnWhenLiveConversationContainsOnlyCleanHistory() {
        assertFalse(
            LocalAiConversationEphemeralContextPolicy.shouldRebuildBeforeNextTurn(false)
        )
    }

    @Test
    fun failedFirstTurnWithEphemeralInputStillRequiresRefreshWithoutSuccessfulHistory() {
        val history = LocalAiConversationHistory()
        assertFalse(history.hasSuccessfulTurn())
        assertTrue(
            LocalAiConversationEphemeralContextPolicy.shouldRebuildBeforeNextTurn(true)
        )
    }

    @Test
    fun bindsFreshEmptyNativeConversationWithoutReset() {
        assertTrue(!LocalAiConversationSessionPolicy.shouldReset(null, 11L, false))
    }

    @Test
    fun preservesHistoryForTheSameConversationId() {
        assertTrue(!LocalAiConversationSessionPolicy.shouldReset(11L, 11L, true))
    }

    @Test
    fun resetsNativeStateWhenSwitchingConversationIds() {
        assertTrue(LocalAiConversationSessionPolicy.shouldReset(11L, 12L, true))
    }

    @Test
    fun resetsUnboundNativeStateWhenItAlreadyContainsConversationData() {
        assertTrue(LocalAiConversationSessionPolicy.shouldReset(null, 12L, true))
    }

    @Test
    fun rejectsMissingOrInvalidConversationIds() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiConversationSessionPolicy.shouldReset(null, 0L, false)
        }
    }

    @Test
    fun blankUserInputIsRejected() {
        val history = LocalAiConversationHistory()

        assertThrows(IllegalArgumentException::class.java) {
            history.appendSuccessfulTurn(" ", "answer")
        }
        assertTrue(history.snapshot().turns.isEmpty())
        assertFalse(history.hasSuccessfulTurn())
    }

    @Test
    fun evictsOnlyOldestWholeTurnsWhenTurnLimitIsExceeded() {
        val history = LocalAiConversationHistory(
            maxRetainedTurns = 2,
            maxRetainedCharacters = 100
        )
        history.appendSuccessfulTurn("u1", "m1")
        history.appendSuccessfulTurn("u2", "m2")
        history.appendSuccessfulTurn("u3", "m3")

        val snapshot = history.snapshot()
        assertEquals(
            listOf(
                LocalAiCompletedTurn("u2", "m2"),
                LocalAiCompletedTurn("u3", "m3")
            ),
            snapshot.turns
        )
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(4L, snapshot.omittedCharacterCount)
        assertEquals(3L, snapshot.successfulTurnCount)
        assertTrue(history.hasSuccessfulTurn())
    }

    @Test
    fun enforcesUtf16CharacterBudgetWithoutCuttingACompletedTurn() {
        val history = LocalAiConversationHistory(
            maxRetainedTurns = 10,
            maxRetainedCharacters = 8
        )
        history.appendSuccessfulTurn("abc", "def")
        history.appendSuccessfulTurn("123", "456")

        val snapshot = history.snapshot()
        assertEquals(listOf(LocalAiCompletedTurn("123", "456")), snapshot.turns)
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(6L, snapshot.omittedCharacterCount)
        assertEquals(6, snapshot.turns.single().userText.length +
            snapshot.turns.single().modelText.length)
    }

    @Test
    fun omitsAnOversizedNewestTurnWholeAndKeepsSuccessStateForFallback() {
        val history = LocalAiConversationHistory(
            maxRetainedTurns = 10,
            maxRetainedCharacters = 8
        )
        history.appendSuccessfulTurn("1234567", "xx")

        val snapshot = history.snapshot()
        assertTrue(snapshot.turns.isEmpty())
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(9L, snapshot.omittedCharacterCount)
        assertEquals(1L, snapshot.successfulTurnCount)
        assertTrue(history.hasSuccessfulTurn())
        assertTrue(
            LocalAiConversationHistoryPolicy.systemInstruction("base", snapshot)
                .contains("已省略 1 轮")
        )
    }

    @Test
    fun omissionInstructionIsAbsentWhenNoTurnWasOmitted() {
        val history = LocalAiConversationHistory()
        history.appendSuccessfulTurn("question", "answer")

        assertEquals(
            "base",
            LocalAiConversationHistoryPolicy.systemInstruction("base", history.snapshot())
        )
    }

    @Test
    fun restoresBoundedHistoryAndOmissionMetadataAcrossBackendRecreation() {
        val original = LocalAiConversationHistory(maxRetainedTurns = 1, maxRetainedCharacters = 50)
        original.appendSuccessfulTurn("older", "answer one")
        original.appendSuccessfulTurn("newer", "answer two")

        val restored = LocalAiConversationHistory(maxRetainedTurns = 1, maxRetainedCharacters = 50)
        restored.restore(original.snapshot())

        val snapshot = restored.snapshot()
        assertEquals(listOf(LocalAiCompletedTurn("newer", "answer two")), snapshot.turns)
        assertEquals(1, snapshot.omittedTurnCount)
        assertEquals(2L, snapshot.successfulTurnCount)
        assertTrue(restored.hasSuccessfulTurn())
    }

    @Test
    fun clearResetsTurnsOmissionAndSuccessfulTurnState() {
        val history = LocalAiConversationHistory(maxRetainedTurns = 1, maxRetainedCharacters = 20)
        history.appendSuccessfulTurn("first", "answer one")
        history.appendSuccessfulTurn("second", "answer two")

        history.clear()

        val snapshot = history.snapshot()
        assertTrue(snapshot.turns.isEmpty())
        assertEquals(0, snapshot.omittedTurnCount)
        assertEquals(0L, snapshot.omittedCharacterCount)
        assertEquals(0L, snapshot.successfulTurnCount)
        assertFalse(history.hasSuccessfulTurn())
    }

    @Test
    fun acceptsPositiveIntegerConversationIdsWithoutChangingTheirValue() {
        assertEquals(42L, LocalAiConversationIdPolicy.parse(42))
        assertEquals(3_000_000_000L, LocalAiConversationIdPolicy.parse(3_000_000_000L))
    }

    @Test
    fun rejectsNonIntegerAndInvalidConversationIdValues() {
        assertEquals(null, LocalAiConversationIdPolicy.parse(null))
        assertEquals(null, LocalAiConversationIdPolicy.parse(0))
        assertEquals(null, LocalAiConversationIdPolicy.parse(-1L))
        assertEquals(null, LocalAiConversationIdPolicy.parse(1.5))
        assertEquals(null, LocalAiConversationIdPolicy.parse("42"))
    }

    @Test
    fun reportsConversationTokenCountWithoutInferringABudget() {
        val observation = LocalAiConversationTokenObservationPolicy.fromTokenCount(1234)

        assertEquals(1234, observation.tokenCount)
        assertEquals(
            LocalAiConversationTokenObservation.Status.OBSERVED,
            observation.status
        )
    }

    @Test
    fun reportsPositiveModelDeclaredContextLimitWithoutCreatingABudget() {
        val observation =
            LocalAiModelContextLimitObservationPolicy.fromMaxContextTokens(32_768)

        assertEquals(32_768, observation.maxContextTokens)
        assertEquals(
            LocalAiModelContextLimitObservation.Status.OBSERVED,
            observation.status
        )
    }

    @Test
    fun missingZeroOrNegativeModelContextLimitsRemainUnknown() {
        listOf(null, 0, -1).forEach { limit ->
            val observation =
                LocalAiModelContextLimitObservationPolicy.fromMaxContextTokens(limit)
            assertEquals(null, observation.maxContextTokens)
            assertEquals(
                LocalAiModelContextLimitObservation.Status.UNKNOWN,
                observation.status
            )
        }
        assertEquals(
            LocalAiModelContextLimitObservation.Status.UNKNOWN,
            LocalAiModelContextLimitObservationPolicy.unknown().status
        )
    }

    @Test
    fun missingOrNegativeConversationTokenCountsRemainUnknown() {
        listOf(null, -1).forEach { count ->
            val observation = LocalAiConversationTokenObservationPolicy.fromTokenCount(count)
            assertEquals(null, observation.tokenCount)
            assertEquals(
                LocalAiConversationTokenObservation.Status.UNKNOWN,
                observation.status
            )
        }
        assertEquals(
            LocalAiConversationTokenObservation.Status.UNKNOWN,
            LocalAiConversationTokenObservationPolicy.unknown().status
        )
    }


    @Test
    fun finalizationCompletionIsIdempotentForTheSameRequestAndSession() {
        val ledger = LocalAiReasoningTurnCompletionLedger()
        val requestId = "0123456789abcdef0123456789abcdef"

        assertEquals(null, ledger.status(requestId, 42L))
        ledger.markCompleted(
            requestId,
            42L,
            LocalAiReasoningTurnCompletionStatus.FINALIZED
        )

        assertEquals(
            LocalAiReasoningTurnCompletionStatus.FINALIZED,
            ledger.status(requestId, 42L)
        )
        ledger.markCompleted(
            requestId,
            42L,
            LocalAiReasoningTurnCompletionStatus.FINALIZED
        )
    }

    @Test
    fun completionLedgerRejectsSessionAndTerminalStateConflicts() {
        val ledger = LocalAiReasoningTurnCompletionLedger()
        val requestId = "0123456789abcdef0123456789abcdef"
        ledger.markCompleted(
            requestId,
            42L,
            LocalAiReasoningTurnCompletionStatus.FINALIZED
        )

        assertThrows(IllegalArgumentException::class.java) {
            ledger.status(requestId, 43L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            ledger.markCompleted(
                requestId,
                42L,
                LocalAiReasoningTurnCompletionStatus.REJECTED
            )
        }
    }

    @Test
    fun completionLedgerEvictsOldestEntriesWithoutChangingRecentStatuses() {
        val ledger = LocalAiReasoningTurnCompletionLedger(maxEntries = 2)
        val first = "00000000000000000000000000000001"
        val second = "00000000000000000000000000000002"
        val third = "00000000000000000000000000000003"
        ledger.markCompleted(first, 42L, LocalAiReasoningTurnCompletionStatus.REJECTED)
        ledger.markCompleted(second, 42L, LocalAiReasoningTurnCompletionStatus.FINALIZED)
        ledger.markCompleted(third, 42L, LocalAiReasoningTurnCompletionStatus.REJECTED)

        assertEquals(null, ledger.status(first, 42L))
        assertEquals(
            LocalAiReasoningTurnCompletionStatus.FINALIZED,
            ledger.status(second, 42L)
        )
        assertEquals(
            LocalAiReasoningTurnCompletionStatus.REJECTED,
            ledger.status(third, 42L)
        )
    }

    @Test
    fun keepsReasoningProtocolMetadataInItsOwnUntruncatedInputSection() {
        val metadata = "x".repeat(LocalAiReasoningTurnPolicy.maxSupplementalContextCharacters)
        val prepared = LocalAiMessageInputPolicy.prepare(
            userText = "原始问题",
            context = "knowledge".repeat(1_000),
            reasoningContext = metadata
        )

        assertTrue(prepared.modelInput.contains(metadata))
        assertTrue(prepared.modelInput.contains("【App 提供的本轮结构化推理协议元数据（独立受限区）】"))
        assertTrue(prepared.modelInput.endsWith("【用户原文】\n原始问题"))
        assertEquals("原始问题", prepared.historyUserText)
    }

    @Test
    fun rejectsReasoningProtocolMetadataAboveItsExplicitCharacterBound() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiMessageInputPolicy.prepare(
                userText = "原始问题",
                context = "",
                reasoningContext = "x".repeat(
                    LocalAiReasoningTurnPolicy.maxSupplementalContextCharacters + 1
                )
            )
        }
    }

    @Test
    fun bindsPendingReasoningTurnToOneRequestAndOneConversation() {
        val history = LocalAiConversationHistory().apply {
            appendSuccessfulTurn("previous", "completed")
        }
        val pending = LocalAiReasoningTurnPolicy.createPendingTurn(
            requestId = "0123456789abcdef0123456789abcdef",
            conversationId = 42L,
            userText = "原始问题",
            previousHistory = history.snapshot()
        )

        assertEquals(
            pending,
            LocalAiReasoningTurnPolicy.requireMatchingPendingTurn(
                pending,
                "0123456789abcdef0123456789abcdef",
                42L
            )
        )
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiReasoningTurnPolicy.requireMatchingPendingTurn(
                pending,
                "fedcba9876543210fedcba9876543210",
                42L
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiReasoningTurnPolicy.requireMatchingPendingTurn(
                pending,
                pending.requestId,
                43L
            )
        }
    }

    @Test
    fun rejectsInvalidReasoningRequestIdentityBeforeCreatingPendingTurn() {
        val history = LocalAiConversationHistory().snapshot()
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiReasoningTurnPolicy.createPendingTurn(
                requestId = "request-1",
                conversationId = 42L,
                userText = "原始问题",
                previousHistory = history
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            LocalAiReasoningTurnPolicy.createPendingTurn(
                requestId = "0123456789abcdef0123456789abcdef",
                conversationId = 42L,
                userText = " ",
                previousHistory = history
            )
        }
    }

}
