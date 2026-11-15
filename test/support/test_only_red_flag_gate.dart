import 'package:nihaisha_app/services/red_flag_gate.dart';
import 'package:nihaisha_app/services/red_flag_preflight.dart';

/// Test-only synthetic no-match assessment for exercising downstream UI flows.
///
/// This is not a medical detector and must never be imported by production
/// code. Production remains fail-closed until a medically reviewed detector is
/// installed with real provenance and complete coverage.
class TestOnlyReviewedNoMatchDetector implements RedFlagDetector {
  const TestOnlyReviewedNoMatchDetector();

  @override
  Future<RedFlagAssessment?> assess(RedFlagInput input) async {
    return RedFlagAssessment(
      inputSource: input.source,
      detectorId: 'test-only-reviewed-no-match',
      detectorVersion: 'test-only-1',
      ruleSetVersion: 'test-only-policy-fixture',
      subject: RedFlagSubject.knowledge,
      time: RedFlagTime.hypothetical,
      polarity: RedFlagPolarity.negated,
      ruleSetReviewed: true,
      detectorCoverageComplete: true,
      matchedRuleIds: const [],
    );
  }
}

const testOnlyReviewedNoMatchRedFlagGate = RedFlagGate(
  detector: TestOnlyReviewedNoMatchDetector(),
  timeout: Duration(seconds: 1),
);
