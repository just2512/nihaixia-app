import '../services/entitlement_service.dart';
import 'feature_authorizer.dart';
import 'feature_authorizer_scope.dart';
import 'license_platform.dart';
import 'license_verifier.dart';
import 'release_license_key_ring.dart';

/// Creates the one application-wide authorizer at the composition root.
///
/// Debug and ordinary tests remain fail-closed without loading a production
/// trust anchor. Release cannot start with an empty or test-only key ring.
FeatureAuthorizer createAppFeatureAuthorizer({required bool release}) {
  if (!release) return const UnconfiguredFeatureAuthorizer();

  final keyRing = ReleaseLicenseKeyRingFactory.fromEnvironment(
    release: true,
  );
  return EntitlementService(
    platform: MethodChannelLicensePlatform(),
    verifier: LicenseVerifier(keyRing: keyRing),
  );
}
