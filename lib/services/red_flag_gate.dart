import 'dart:async';

import 'red_flag_preflight.dart';

/// Ephemeral input passed to a detector. Callers must not persist [text] here;
/// the gate only uses it during the current request.
class RedFlagInput {
  const RedFlagInput({
    required this.source,
    this.text,
  });

  final RedFlagInputSource source;
  final String? text;
}

/// Implementations must return an assessment from a versioned detector.
/// A null assessment means the input was not safely assessed.
abstract interface class RedFlagDetector {
  Future<RedFlagAssessment?> assess(RedFlagInput input);
}

/// Fail-closed boundary around detector execution and policy evaluation.
///
/// This class intentionally contains no medical vocabulary, thresholds or
/// emergency copy. It does not become a production detector until a reviewed
/// implementation is supplied and every production entrypoint calls it.
class RedFlagGate {
  const RedFlagGate({
    required this.detector,
    required this.timeout,
    this.preflight = const RedFlagPreflight(),
  }) : assert(timeout > Duration.zero);

  final RedFlagDetector? detector;
  final Duration timeout;
  final RedFlagPreflight preflight;

  Future<RedFlagPreflightResult> evaluate(RedFlagInput input) async {
    if (input.source == RedFlagInputSource.unknown) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'INPUT_SOURCE_UNKNOWN',
      );
    }
    if (input.source == RedFlagInputSource.currentText &&
        (input.text == null || input.text!.trim().isEmpty)) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'INPUT_CONTENT_UNAVAILABLE',
      );
    }

    final activeDetector = detector;
    if (activeDetector == null) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'DETECTOR_NOT_CONFIGURED',
      );
    }

    final RedFlagAssessment? assessment;
    try {
      assessment = await activeDetector.assess(input).timeout(timeout);
    } on TimeoutException {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'DETECTOR_TIMEOUT',
      );
    } catch (_) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'DETECTOR_EXECUTION_FAILED',
      );
    }

    if (assessment == null) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'DETECTOR_ASSESSMENT_MISSING',
      );
    }
    if (assessment.inputSource != input.source) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'INPUT_SOURCE_MISMATCH',
      );
    }
    return preflight.evaluate(assessment);
  }
}
