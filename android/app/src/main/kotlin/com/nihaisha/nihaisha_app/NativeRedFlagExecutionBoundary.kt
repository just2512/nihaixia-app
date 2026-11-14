package com.nihaisha.nihaisha_app

/**
 * Provenance-preserving inputs for the Android MethodChannel boundary.
 *
 * This is an injection seam only. It deliberately contains no medical
 * vocabulary, thresholds, or emergency-response copy.
 */
enum class NativeRedFlagInputSource {
    CURRENT_TEXT,
    TOOL_ARGUMENTS,
    IMAGE_ATTACHMENT,
    AUDIO_ATTACHMENT,
    STRUCTURED_INPUT,
    HISTORY_RESTORE,
    UNKNOWN
}

enum class NativeRedFlagStatus {
    CLEAR,
    BLOCK_URGENT,
    CLARIFY,
    REVIEW_REQUIRED
}

data class NativeRedFlagInput(
    val source: NativeRedFlagInputSource,
    val text: String?
)

data class NativeRedFlagVerdict(
    val inputSource: NativeRedFlagInputSource,
    val status: NativeRedFlagStatus,
    val detectorId: String?,
    val detectorVersion: String?,
    val ruleSetVersion: String?,
    val ruleSetReviewed: Boolean,
    val detectorCoverageComplete: Boolean,
    val reason: String
)

fun interface NativeRedFlagDetector {
    fun assess(input: NativeRedFlagInput): NativeRedFlagVerdict?
}

/**
 * Fail-closed validation around a medically reviewed detector supplied by the
 * host application. No detector is installed in this change.
 *
 * Raw image/audio attachments cannot be cleared by accompanying prompt text:
 * a separately provenance-labelled trusted transcript/observation is required.
 */
class NativeRedFlagExecutionBoundary(
    private val detector: NativeRedFlagDetector?
) {
    fun evaluate(input: NativeRedFlagInput): NativeRedFlagVerdict {
        if (input.source == NativeRedFlagInputSource.UNKNOWN) {
            return reviewRequired(input.source, "INPUT_SOURCE_UNKNOWN")
        }
        if (input.source == NativeRedFlagInputSource.IMAGE_ATTACHMENT ||
            input.source == NativeRedFlagInputSource.AUDIO_ATTACHMENT
        ) {
            return reviewRequired(input.source, "RAW_ATTACHMENT_NOT_ASSESSED")
        }
        if (input.text.isNullOrBlank()) {
            return reviewRequired(input.source, "INPUT_CONTENT_UNAVAILABLE")
        }
        val activeDetector = detector
            ?: return reviewRequired(input.source, "DETECTOR_NOT_CONFIGURED")

        val verdict = try {
            activeDetector.assess(input)
        } catch (_: Throwable) {
            null
        } ?: return reviewRequired(input.source, "DETECTOR_ASSESSMENT_MISSING")

        if (verdict.inputSource != input.source) {
            return reviewRequired(input.source, "INPUT_SOURCE_MISMATCH")
        }
        if (verdict.detectorId.isNullOrBlank() ||
            verdict.detectorVersion.isNullOrBlank() ||
            verdict.ruleSetVersion.isNullOrBlank()
        ) {
            return reviewRequired(input.source, "DETECTOR_PROVENANCE_MISSING")
        }
        if (!verdict.ruleSetReviewed || !verdict.detectorCoverageComplete) {
            return reviewRequired(input.source, "RULESET_OR_COVERAGE_UNVERIFIED")
        }
        return verdict
    }

    private fun reviewRequired(
        source: NativeRedFlagInputSource,
        reason: String
    ) = NativeRedFlagVerdict(
        inputSource = source,
        status = NativeRedFlagStatus.REVIEW_REQUIRED,
        detectorId = null,
        detectorVersion = null,
        ruleSetVersion = null,
        ruleSetReviewed = false,
        detectorCoverageComplete = false,
        reason = reason
    )
}
