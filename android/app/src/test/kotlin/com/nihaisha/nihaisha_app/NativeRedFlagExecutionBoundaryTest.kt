package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeRedFlagExecutionBoundaryTest {
    private fun clearVerdict(
        source: NativeRedFlagInputSource = NativeRedFlagInputSource.CURRENT_TEXT
    ) = NativeRedFlagVerdict(
        inputSource = source,
        status = NativeRedFlagStatus.CLEAR,
        detectorId = "test-only-detector",
        detectorVersion = "test-only-1",
        ruleSetVersion = "test-reviewed-rule-set-1",
        ruleSetReviewed = true,
        detectorCoverageComplete = true,
        reason = "TEST_CLEAR"
    )

    @Test
    fun missingDetectorNeverReturnsClear() {
        val verdict = NativeRedFlagExecutionBoundary(null).evaluate(
            NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text")
        )

        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, verdict.status)
        assertEquals("DETECTOR_NOT_CONFIGURED", verdict.reason)
    }

    @Test
    fun onlyVersionedReviewedCompleteAssessmentCanClear() {
        val boundary = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { input -> clearVerdict(input.source) }
        )

        val verdict = boundary.evaluate(
            NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text")
        )

        assertEquals(NativeRedFlagStatus.CLEAR, verdict.status)
    }

    @Test
    fun unreviewedOrVersionlessClearIsRejected() {
        val unreviewed = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { input ->
                clearVerdict(input.source).copy(ruleSetReviewed = false)
            }
        ).evaluate(NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text"))
        val versionless = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { input ->
                clearVerdict(input.source).copy(detectorVersion = null)
            }
        ).evaluate(NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text"))

        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, unreviewed.status)
        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, versionless.status)
    }

    @Test
    fun unknownInputAndRawAttachmentsNeverReachDetector() {
        var detectorCalls = 0
        val boundary = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { input ->
                detectorCalls += 1
                clearVerdict(input.source)
            }
        )

        val unknown = boundary.evaluate(
            NativeRedFlagInput(NativeRedFlagInputSource.UNKNOWN, "text")
        )
        val image = boundary.evaluate(
            NativeRedFlagInput(NativeRedFlagInputSource.IMAGE_ATTACHMENT, "prompt text")
        )
        val audio = boundary.evaluate(
            NativeRedFlagInput(NativeRedFlagInputSource.AUDIO_ATTACHMENT, "prompt text")
        )

        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, unknown.status)
        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, image.status)
        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, audio.status)
        assertEquals("RAW_ATTACHMENT_NOT_ASSESSED", image.reason)
        assertEquals(0, detectorCalls)
    }

    @Test
    fun detectorExceptionAndSourceMismatchFailClosed() {
        val failed = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { throw IllegalStateException("private detail") }
        ).evaluate(NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text"))
        val mismatch = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { clearVerdict(NativeRedFlagInputSource.HISTORY_RESTORE) }
        ).evaluate(NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text"))

        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, failed.status)
        assertEquals("DETECTOR_ASSESSMENT_MISSING", failed.reason)
        assertFalse(failed.reason.contains("private detail"))
        assertEquals(NativeRedFlagStatus.REVIEW_REQUIRED, mismatch.status)
        assertEquals("INPUT_SOURCE_MISMATCH", mismatch.reason)
    }

    @Test
    fun nonClearReviewedVerdictRemainsNonClear() {
        val boundary = NativeRedFlagExecutionBoundary(
            NativeRedFlagDetector { input ->
                clearVerdict(input.source).copy(status = NativeRedFlagStatus.CLARIFY)
            }
        )

        val verdict = boundary.evaluate(
            NativeRedFlagInput(NativeRedFlagInputSource.CURRENT_TEXT, "user text")
        )

        assertEquals(NativeRedFlagStatus.CLARIFY, verdict.status)
        assertTrue(verdict.status != NativeRedFlagStatus.CLEAR)
    }
}
