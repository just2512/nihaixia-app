import 'package:flutter/widgets.dart';

import 'feature_authorizer.dart';

/// Fail-closed authorizer used until a production release key ring is wired.
///
/// Ordinary chat and single-capability tool calls do not request a paid
/// feature. A cross-capability AI plan is denied when the application has not
/// supplied a verified entitlement implementation.
class UnconfiguredFeatureAuthorizer implements FeatureAuthorizer {
  const UnconfiguredFeatureAuthorizer();

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    return FeatureAuthorizationDecision.denied(
      featureId: featureId,
      reason: FeatureAuthorizationFailureReason.unlicensed,
    );
  }
}

/// Dependency scope for production authorization and deterministic tests.
/// The fallback is deliberately fail-closed; it never grants a paid feature.
class FeatureAuthorizerScope extends InheritedWidget {
  const FeatureAuthorizerScope({
    required this.authorizer,
    required super.child,
    super.key,
  });

  final FeatureAuthorizer authorizer;

  static FeatureAuthorizer of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<FeatureAuthorizerScope>()
            ?.authorizer ??
        const UnconfiguredFeatureAuthorizer();
  }

  @override
  bool updateShouldNotify(FeatureAuthorizerScope oldWidget) =>
      !identical(authorizer, oldWidget.authorizer);
}
