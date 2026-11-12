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
  });

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
    // A prompt accompanying an image/audio file is not evidence that the
    // attachment itself was assessed. Callers must first produce a trusted,
    // provenance-labelled attachmentTranscript input.
    if (input.source == RedFlagInputSource.imageAttachment ||
        input.source == RedFlagInputSource.audioAttachment) {
      return const RedFlagPreflightResult(
        RedFlagPreflightStatus.reviewRequired,
        'RAW_ATTACHMENT_NOT_ASSESSED',
      );
    }
    // This contract accepts text/transcript inputs only. An absent transcript
    // cannot be treated as a complete assessment.
    if (input.text == null || input.text!.trim().isEmpty) {
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


/// Result of a gate-protected operation. A blocked operation has no [value]
/// and [executed] is false; callers must not infer that business work started.
class RedFlagGateRun<T> {
  const RedFlagGateRun.blocked(this.preflight)
      : executed = false,
        value = null;

  const RedFlagGateRun.executed(this.preflight, this.value)
      : executed = true;

  final RedFlagPreflightResult preflight;
  final bool executed;
  final T? value;
}

/// Shared sequencing seam for production entrypoints and deterministic tests.
///
/// The operation callback is invoked only after the configured detector and
/// policy both return CLEAR. This helper does not install a detector, create
/// medical rules, or decide which product flows should require review.
extension RedFlagGateExecution on RedFlagGate {
  Future<RedFlagGateRun<T>> runBefore<T>({
    required RedFlagInput input,
    required Future<T> Function() operation,
  }) async {
    final result = await evaluate(input);
    if (!result.mayContinueOrdinaryFlow) {
      return RedFlagGateRun<T>.blocked(result);
    }
    final value = await operation();
    return RedFlagGateRun<T>.executed(result, value);
  }
}
