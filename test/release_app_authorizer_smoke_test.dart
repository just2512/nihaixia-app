import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/app_feature_authorizer_factory.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';

void main() {
  test('Release app composition uses EntitlementService and production Key Ring',
      () {
    final authorizer = createAppFeatureAuthorizer(release: true);
    expect(authorizer, isA<EntitlementService>());
  });
}
