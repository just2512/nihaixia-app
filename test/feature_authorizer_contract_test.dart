import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';

class _FakeFeatureAuthorizer implements FeatureAuthorizer {
  _FakeFeatureAuthorizer(this.decision);

  final FeatureAuthorizationDecision decision;
  final requestedFeatureIds = <String>[];

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    requestedFeatureIds.add(featureId);
    return decision;
  }
}

void main() {
  group('FeatureAuthorizationDecision', () {
    test('allowed is explicit and has no failure reason', () {
      const featureId = 'ai_advanced';
      final decision =
          FeatureAuthorizationDecision.allowed(featureId: featureId);

      expect(decision.featureId, featureId);
      expect(decision.status, FeatureAuthorizationStatus.allowed);
      expect(decision.reason, isNull);
      expect(decision.isAllowed, isTrue);
    });

    test('denied is distinct from temporarily unavailable', () {
      final denied = FeatureAuthorizationDecision.denied(
        featureId: 'contextual_assistant',
        reason: FeatureAuthorizationFailureReason.signatureInvalid,
      );
      final unavailable =
          FeatureAuthorizationDecision.temporarilyUnavailable(
        featureId: 'contextual_assistant',
        reason: FeatureAuthorizationFailureReason.initializationTimeout,
      );

      expect(denied.status, FeatureAuthorizationStatus.denied);
      expect(denied.reason, FeatureAuthorizationFailureReason.signatureInvalid);
      expect(unavailable.status,
          FeatureAuthorizationStatus.temporarilyUnavailable);
      expect(unavailable.reason,
          FeatureAuthorizationFailureReason.initializationTimeout);
      expect(denied.isAllowed, isFalse);
      expect(unavailable.isAllowed, isFalse);
    });

    test('preserves each stable authorization failure reason', () {
      const featureId = 'ai_advanced';
      const reasons = FeatureAuthorizationFailureReason.values;

      for (final reason in reasons) {
        final denied = FeatureAuthorizationDecision.denied(
          featureId: featureId,
          reason: reason,
        );
        final unavailable =
            FeatureAuthorizationDecision.temporarilyUnavailable(
          featureId: featureId,
          reason: reason,
        );

        expect(denied.status, FeatureAuthorizationStatus.denied);
        expect(denied.reason, reason);
        expect(unavailable.status,
            FeatureAuthorizationStatus.temporarilyUnavailable);
        expect(unavailable.reason, reason);
      }
    });

    test('all decision factories reject invalid feature IDs', () {
      for (final featureId in ['', ' ', ' ai_advanced', 'ai_advanced ']) {
        expect(
          () => FeatureAuthorizationDecision.denied(
            featureId: featureId,
            reason: FeatureAuthorizationFailureReason.signatureInvalid,
          ),
          throwsArgumentError,
        );
        expect(
          () => FeatureAuthorizationDecision.temporarilyUnavailable(
            featureId: featureId,
            reason: FeatureAuthorizationFailureReason.initializationTimeout,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects empty, whitespace-padded or blank feature IDs', () {
      for (final featureId in ['', ' ', ' ai_advanced']) {
        expect(
          () => FeatureAuthorizationDecision.allowed(
            featureId: featureId,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  test('FeatureAuthorizer is an injected async query, not a global gate', () async {
    const featureId = 'ai_advanced';
    final expected =
        FeatureAuthorizationDecision.temporarilyUnavailable(
      featureId: featureId,
      reason: FeatureAuthorizationFailureReason.storageUnavailable,
    );
    final authorizer = _FakeFeatureAuthorizer(expected);

    final actual = await authorizer.authorize(featureId);

    expect(actual, same(expected));
    expect(authorizer.requestedFeatureIds, [featureId]);
  });

  test('includes stable token, issuer and product failure reasons', () {
    const expected = {
      FeatureAuthorizationFailureReason.unlicensed,
      FeatureAuthorizationFailureReason.featureNotGranted,
      FeatureAuthorizationFailureReason.licenseRevoked,
      FeatureAuthorizationFailureReason.issuerCompromised,
      FeatureAuthorizationFailureReason.invalidTokenFormat,
      FeatureAuthorizationFailureReason.wrongApplication,
      FeatureAuthorizationFailureReason.wrongProduct,
    };
    expect(
      FeatureAuthorizationFailureReason.values.toSet(),
      containsAll(expected),
    );
  });
}
