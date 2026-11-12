/// Deterministic policy evaluation for a separately reviewed red-flag detector.
///
/// This class deliberately does not infer medical meaning from raw text. A
/// reviewed detector must supply candidate rule IDs and semantic scope. Until
/// the rule set and detector coverage are reviewed, the result cannot be CLEAR.
enum RedFlagInputSource {
  currentText,
  attachmentTranscript,
  historyRestore,
  structuredInterview,
  toolArguments,
  unknown,
}

enum RedFlagSubject { self, other, knowledge, unknown }

enum RedFlagTime { current, past, hypothetical, unknown }

enum RedFlagPolarity { affirmed, negated, quoted, unknown }

enum RedFlagPreflightStatus {
  clear,
  blockUrgent,
  clarify,
  reviewRequired,
}

class RedFlagAssessment {
  const RedFlagAssessment({
    required this.subject,
    required this.time,
    required this.polarity,
    required this.ruleSetReviewed,
    required this.detectorCoverageComplete,
    this.inputSource = RedFlagInputSource.unknown,
    this.detectorId,
    this.detectorVersion,
    this.ruleSetVersion,
    this.matchedRuleIds = const <String>[],
  });

  /// Origin channel of the material evaluated by the detector. History and
  /// attachment-derived text must retain their origin rather than being
  /// silently reclassified as current user text.
  final RedFlagInputSource inputSource;

  /// Versioned provenance for the detector and the exact reviewed rule set.
  /// These identifiers contain no user content and are required before CLEAR.
  final String? detectorId;
  final String? detectorVersion;
  final String? ruleSetVersion;

  final RedFlagSubject subject;
  final RedFlagTime time;
  final RedFlagPolarity polarity;

  /// True only after the medical review record for this exact rule-set version
  /// has been accepted. An unreviewed candidate list must never clear input.
  final bool ruleSetReviewed;

  /// True only when the detector has evaluated every supported input channel
  /// for this assessment (including a trusted transcript for attachments).
  final bool detectorCoverageComplete;

  /// IDs emitted by the reviewed detector, never free-form model output.
  final List<String> matchedRuleIds;
}

class RedFlagPreflightResult {
  const RedFlagPreflightResult(this.status, this.reason);

  final RedFlagPreflightStatus status;
  final String reason;

  bool get mayContinueOrdinaryFlow =>
      status == RedFlagPreflightStatus.clear;
}

class RedFlagPreflight {
  const RedFlagPreflight();

  RedFlagPreflightResult evaluate(RedFlagAssessment assessment) {
    if (assessment.inputSource == RedFlagInputSource.unknown ||
        _isBlank(assessment.detectorId) ||
        _isBlank(assessment.detectorVersion) ||
        _isBlank(assessment.ruleSetVersion) ||
        assessment.matchedRuleIds.any(_isBlank)) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'DETECTOR_PROVENANCE_MISSING',
      );
    }

    if (assessment.matchedRuleIds.isEmpty) {
      if (!assessment.ruleSetReviewed ||
          !assessment.detectorCoverageComplete) {
        return const RedFlagPreflightResult(
          RedFlagPreflightStatus.reviewRequired,
          'RULESET_OR_COVERAGE_UNVERIFIED',
        );
      }
      if (assessment.subject == RedFlagSubject.unknown ||
          assessment.time == RedFlagTime.unknown ||
          assessment.polarity == RedFlagPolarity.unknown) {
        return const RedFlagPreflightResult(
          RedFlagPreflightStatus.clarify,
          'SEMANTIC_SCOPE_UNKNOWN',
        );
      }
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.clear,
        'NO_REVIEWED_RED_FLAG_MATCH',
      );
    }

    // A candidate match is not a clinical conclusion. If the medical rules
    // are not reviewed, do not promote it to an official emergency decision
    // and do not allow ordinary model/tool execution.
    if (!assessment.ruleSetReviewed ||
        !assessment.detectorCoverageComplete) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'MATCH_WITH_UNVERIFIED_RULESET_OR_COVERAGE',
      );
    }

    if (assessment.subject == RedFlagSubject.unknown ||
        assessment.time == RedFlagTime.unknown ||
        assessment.polarity == RedFlagPolarity.unknown ||
        assessment.polarity == RedFlagPolarity.quoted) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.clarify,
        'MATCH_WITH_AMBIGUOUS_SEMANTIC_SCOPE',
      );
    }

    // Another person's current emergency is still urgent, but must not be
    // represented as the user's own symptom. Keep the urgent path explicit.
    if (assessment.subject == RedFlagSubject.other &&
        assessment.time == RedFlagTime.current &&
        assessment.polarity == RedFlagPolarity.affirmed) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.blockUrgent,
        'CURRENT_OTHER_PERSON_AFFIRMED_MATCH',
      );
    }

    // Explicit knowledge discussion, past-only history, hypothetical
    // statements, and negation are not current affirmed emergency reports.
    if (assessment.subject == RedFlagSubject.knowledge ||
        assessment.time == RedFlagTime.past ||
        assessment.time == RedFlagTime.hypothetical ||
        assessment.polarity == RedFlagPolarity.negated) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.clear,
        'MATCH_OUTSIDE_CURRENT_SELF_AFFIRMED_SCOPE',
      );
    }

    if (assessment.subject == RedFlagSubject.self &&
        assessment.time == RedFlagTime.current &&
        assessment.polarity == RedFlagPolarity.affirmed) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.blockUrgent,
        'CURRENT_SELF_AFFIRMED_MATCH',
      );
    }

    return const RedFlagPreflightResult(
      RedFlagPreflightStatus.clarify,
      'UNCLASSIFIED_SEMANTIC_SCOPE',
    );
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
