import 'package:flutter/widgets.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';
import 'package:nihaisha_app/licensing/feature_authorizer_scope.dart';

/// Explicitly authorizes protected features in tests that exercise the
/// successful contextual-assistant path. Tests for denial must use their own
/// denying or temporarily-unavailable fake.
class TestAllowFeatureAuthorizer implements FeatureAuthorizer {
  const TestAllowFeatureAuthorizer();

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async =>
      FeatureAuthorizationDecision.allowed(featureId: featureId);
}

/// Wraps a test app with an explicit authorization decision. Production
/// defaults remain fail-closed; this helper is never imported by lib/.
class TestAuthorizedFeatureScope extends StatelessWidget {
  const TestAuthorizedFeatureScope({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => FeatureAuthorizerScope(
        authorizer: const TestAllowFeatureAuthorizer(),
        child: child,
      );
}
