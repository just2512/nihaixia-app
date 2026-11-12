import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/red_flag_gate.dart';
import 'package:nihaisha_app/services/red_flag_preflight.dart';

class _FakeDetector implements RedFlagDetector {
  _FakeDetector(this.handler);

  final Future<RedFlagAssessment?> Function(RedFlagInput input) handler;

  @override
  Future<RedFlagAssessment?> assess(RedFlagInput input) => handler(input);
}

RedFlagAssessment _assessment({
  RedFlagInputSource source = RedFlagInputSource.currentText,
  RedFlagSubject subject = RedFlagSubject.knowledge,
  RedFlagTime time = RedFlagTime.current,
  RedFlagPolarity polarity = RedFlagPolarity.affirmed,
  bool reviewed = true,
  bool coverage = true,
  List<String> matches = const [],
}) =>
    RedFlagAssessment(
      inputSource: source,
      detectorId: 'reviewed-detector',
      detectorVersion: '1',
      ruleSetVersion: 'reviewed-2026-11',
      subject: subject,
      time: time,
      polarity: polarity,
      ruleSetReviewed: reviewed,
      detectorCoverageComplete: coverage,
      matchedRuleIds: matches,
    );

void main() {
  const timeout = Duration(milliseconds: 10);

  group('RedFlagGate fail-closed boundary', () {
    test('missing detector never returns CLEAR', () async {
      const gate = RedFlagGate(detector: null, timeout: timeout);
      final result = await gate.evaluate(
        const RedFlagInput(
          source: RedFlagInputSource.currentText,
          text: '查询胸痛的中医理论',
        ),
      );

      expect(result.status, RedFlagPreflightStatus.reviewRequired);
      expect(result.reason, 'DETECTOR_NOT_CONFIGURED');
      expect(result.mayContinueOrdinaryFlow, isFalse);
    });

    test('unknown source and empty current text fail closed before detector', () async {
      var calls = 0;
      final detector = _FakeDetector((_) async {
        calls++;
        return _assessment();
      });
      final gate = RedFlagGate(detector: detector, timeout: timeout);

      final unknown = await gate.evaluate(
        const RedFlagInput(source: RedFlagInputSource.unknown),
      );
      final empty = await gate.evaluate(
        const RedFlagInput(source: RedFlagInputSource.currentText, text: '  '),
      );

      expect(unknown.reason, 'INPUT_SOURCE_UNKNOWN');
      expect(empty.reason, 'INPUT_CONTENT_UNAVAILABLE');
      expect(calls, 0);
    });

    test('detector timeout returns REVIEW_REQUIRED', () async {
      final detector = _FakeDetector((_) => Completer<RedFlagAssessment?>().future);
      final gate = RedFlagGate(detector: detector, timeout: timeout);

      final result = await gate.evaluate(
        const RedFlagInput(
          source: RedFlagInputSource.currentText,
          text: '我现在胸痛',
        ),
      );

      expect(result.status, RedFlagPreflightStatus.reviewRequired);
      expect(result.reason, 'DETECTOR_TIMEOUT');
      expect(result.mayContinueOrdinaryFlow, isFalse);
    });

    test('detector exception returns REVIEW_REQUIRED without exposing exception text', () async {
      final detector = _FakeDetector((_) async => throw StateError('sensitive details'));
      final gate = RedFlagGate(detector: detector, timeout: timeout);

      final result = await gate.evaluate(
        const RedFlagInput(
          source: RedFlagInputSource.currentText,
          text: '我现在胸痛',
        ),
      );

      expect(result.status, RedFlagPreflightStatus.reviewRequired);
      expect(result.reason, 'DETECTOR_EXECUTION_FAILED');
      expect(result.reason, isNot(contains('sensitive details')));
    });

    test('missing assessment and source mismatch return REVIEW_REQUIRED', () async {
      final missing = RedFlagGate(
        detector: _FakeDetector((_) async => null),
        timeout: timeout,
      );
      final mismatch = RedFlagGate(
        detector: _FakeDetector(
          (_) async => _assessment(source: RedFlagInputSource.historyRestore),
        ),
        timeout: timeout,
      );

      final input = const RedFlagInput(
        source: RedFlagInputSource.currentText,
        text: '胸痛知识学习',
      );
      final missingResult = await missing.evaluate(input);
      final mismatchResult = await mismatch.evaluate(input);

      expect(missingResult.reason, 'DETECTOR_ASSESSMENT_MISSING');
      expect(mismatchResult.reason, 'INPUT_SOURCE_MISMATCH');
      expect(missingResult.mayContinueOrdinaryFlow, isFalse);
      expect(mismatchResult.mayContinueOrdinaryFlow, isFalse);
    });

    test('reviewed detector assessment delegates to existing policy', () async {
      final detector = _FakeDetector(
        (input) async => _assessment(source: input.source),
      );
      final gate = RedFlagGate(detector: detector, timeout: timeout);

      final result = await gate.evaluate(
        const RedFlagInput(
          source: RedFlagInputSource.currentText,
          text: '介绍胸痛的中医理论',
        ),
      );

      expect(result.status, RedFlagPreflightStatus.clear);
      expect(result.reason, 'NO_REVIEWED_RED_FLAG_MATCH');
      expect(result.mayContinueOrdinaryFlow, isTrue);
    });

    test('unreviewed or incomplete detector coverage remains REVIEW_REQUIRED', () async {
      for (final assessment in [
        _assessment(reviewed: false),
        _assessment(coverage: false),
      ]) {
        final gate = RedFlagGate(
          detector: _FakeDetector((_) async => assessment),
          timeout: timeout,
        );
        final result = await gate.evaluate(
          const RedFlagInput(
            source: RedFlagInputSource.currentText,
            text: '我现在不舒服',
          ),
        );
        expect(result.status, RedFlagPreflightStatus.reviewRequired);
        expect(result.mayContinueOrdinaryFlow, isFalse);
      }
    });

    test('new attachment and tool-result sources retain their origin', () async {
      for (final source in [
        RedFlagInputSource.imageAttachment,
        RedFlagInputSource.audioAttachment,
        RedFlagInputSource.toolResult,
        RedFlagInputSource.retrievalContext,
      ]) {
        final gate = RedFlagGate(
          detector: _FakeDetector(
            (input) async => _assessment(source: input.source),
          ),
          timeout: timeout,
        );
        final result = await gate.evaluate(RedFlagInput(source: source));
        expect(result.status, RedFlagPreflightStatus.clear);
      }
    });
  });
}
