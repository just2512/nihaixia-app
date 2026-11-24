import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_key_ring_factory.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';

const _configuredRing = String.fromEnvironment('YANJI_LICENSE_KEY_RING');

void main() {
  test('Release Key Ring is fail-closed without config and production-only when configured', () {
    final ring = LicenseKeyRingFactory.fromEnvironment();

    // Ordinary PR/debug test runs have no production public-key material.
    // They must keep the free app bootable with an empty trust ring.
    if (_configuredRing.trim().isEmpty) {
      expect(ring.keyIds, isEmpty);
      return;
    }

    // The tag/manual Release workflow supplies the verified production ring.
    expect(ring.keyIds, isNotEmpty);
    expect(ring.keyIds, everyElement(isNot(startsWith('test-'))));
    expect(ring.keyIds.contains('test-issuer-01'), isFalse);
    expect(
      ring.keyIds.any((id) =>
          ring[id]!.status == LicenseIssuerKeyStatus.active ||
          ring[id]!.status == LicenseIssuerKeyStatus.standby),
      isTrue,
    );
  });
}
