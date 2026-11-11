import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/red_flag_preflight.dart';

void main() {
  const preflight = RedFlagPreflight();

  RedFlagAssessment assessment({
    RedFlagSubject subject = RedFlagSubject.self,
    RedFlagTime time = RedFlagTime.current,
    RedFlagPolarity polarity = RedFlagPolarity.affirmed,
    bool reviewed = true,
    bool coverage = true,
    List<String> matches = const ['candidate-rule-1'],
  }) =>
      RedFlagAssessment(
        subject: subject,
        time: time,
        polarity: polarity,
        ruleSetReviewed: reviewed,
        detectorCoverageComplete: coverage,
        matchedRuleIds: matches,
      );

  group('RedFlagPreflight policy contract', () {
    test('blocks a reviewed, current, affirmed self match', () {
      final result = preflight.evaluate(assessment());
      expect(result.status, RedFlagPreflightStatus.blockUrgent);
      expect(result.mayContinueOrdinaryFlow, isFalse);
    });

    test('blocks another person current emergency without mislabeling subject', () {
      final result = preflight.evaluate(
        assessment(subject: RedFlagSubject.other),
      );
      expect(result.status, RedFlagPreflightStatus.blockUrgent);
      expect(result.reason, 'CURRENT_OTHER_PERSON_AFFIRMED_MATCH');
    });

    test('does not classify knowledge discussion as a current emergency', () {
      final result = preflight.evaluate(
        assessment(subject: RedFlagSubject.knowledge),
      );
      expect(result.status, RedFlagPreflightStatus.clear);
    });

    test('does not classify past-only history as current', () {
      final result = preflight.evaluate(
        assessment(time: RedFlagTime.past),
      );
      expect(result.status, RedFlagPreflightStatus.clear);
    });

    test('does not classify hypothetical statements as current', () {
      final result = preflight.evaluate(
        assessment(time: RedFlagTime.hypothetical),
      );
      expect(result.status, RedFlagPreflightStatus.clear);
    });

    test('does not classify explicit negation as an active signal', () {
      final result = preflight.evaluate(
        assessment(polarity: RedFlagPolarity.negated),
      );
      expect(result.status, RedFlagPreflightStatus.clear);
    });

    test('clarifies unknown subject, time, polarity and quoted matches', () {
      for (final candidate in [
        assessment(subject: RedFlagSubject.unknown),
        assessment(time: RedFlagTime.unknown),
        assessment(polarity: RedFlagPolarity.unknown),
        assessment(polarity: RedFlagPolarity.quoted),
      ]) {
        expect(
          preflight.evaluate(candidate).status,
          RedFlagPreflightStatus.clarify,
        );
      }
    });

    test('never clears an unreviewed candidate rule set', () {
      final result = preflight.evaluate(assessment(reviewed: false));
      expect(result.status, RedFlagPreflightStatus.reviewRequired);
      expect(result.mayContinueOrdinaryFlow, isFalse);
    });

    test('never clears when detector coverage is incomplete', () {
      final result = preflight.evaluate(assessment(coverage: false));
      expect(result.status, RedFlagPreflightStatus.reviewRequired);
      expect(result.mayContinueOrdinaryFlow, isFalse);
    });

    test('no-match is CLEAR only with reviewed complete detector coverage', () {
      final reviewed = preflight.evaluate(assessment(matches: const []));
      expect(reviewed.status, RedFlagPreflightStatus.clear);

      final unreviewed = preflight.evaluate(
        assessment(matches: const [], reviewed: false),
      );
      expect(unreviewed.status, RedFlagPreflightStatus.reviewRequired);
    });

    test('no-match with unknown semantic scope requires clarification', () {
      for (final candidate in [
        assessment(matches: const [], subject: RedFlagSubject.unknown),
        assessment(matches: const [], time: RedFlagTime.unknown),
        assessment(matches: const [], polarity: RedFlagPolarity.unknown),
      ]) {
        final result = preflight.evaluate(candidate);
        expect(result.status, RedFlagPreflightStatus.clarify);
        expect(result.mayContinueOrdinaryFlow, isFalse);
      }
    });

    test('matched but ambiguous semantic scope never clears', () {
      for (final candidate in [
        assessment(subject: RedFlagSubject.unknown),
        assessment(time: RedFlagTime.unknown),
        assessment(polarity: RedFlagPolarity.unknown),
        assessment(polarity: RedFlagPolarity.quoted),
      ]) {
        final result = preflight.evaluate(candidate);
        expect(result.status, RedFlagPreflightStatus.clarify);
        expect(result.mayContinueOrdinaryFlow, isFalse);
      }
    });

    test('other-person negation and past self match are not current emergencies', () {
      final otherNegated = preflight.evaluate(
        assessment(
          subject: RedFlagSubject.other,
          polarity: RedFlagPolarity.negated,
        ),
      );
      final selfPast = preflight.evaluate(
        assessment(time: RedFlagTime.past),
      );
      expect(otherNegated.status, RedFlagPreflightStatus.clear);
      expect(selfPast.status, RedFlagPreflightStatus.clear);
    });

    test('incomplete detector coverage takes precedence over no-match', () {
      final result = preflight.evaluate(
        assessment(matches: const [], coverage: false),
      );
      expect(result.status, RedFlagPreflightStatus.reviewRequired);
      expect(result.mayContinueOrdinaryFlow, isFalse);
    });
  });
}