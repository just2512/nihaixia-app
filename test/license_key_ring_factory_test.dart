import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_key_ring_factory.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';

const _publicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  group('LicenseKeyRingFactory', () {
    test('missing configuration yields an empty fail-closed ring', () {
      final ring = LicenseKeyRingFactory.fromEnvironment(serialized: '');

      expect(ring.keyIds, isEmpty);
      expect(ring['any-issuer'], isNull);
    });

    test('loads immutable issuer public keys and status', () {
      final ring = LicenseKeyRingFactory.fromJson('''
        {
          "keys": [
            {
              "key_id": "issuer-2026-01",
              "public_key_base64url": "$_publicKey",
              "status": "active"
            }
          ]
        }
      ''');

      expect(ring.keyIds, {'issuer-2026-01'});
      expect(ring['issuer-2026-01']!.status, LicenseIssuerKeyStatus.active);
      expect(ring['issuer-2026-01']!.publicKey, List<int>.filled(32, 0));
    });

    test('supports the documented rotation and revocation states', () {
      for (final status in [
        'active',
        'standby',
        'retired',
        'revoked',
        'compromised',
      ]) {
        final ring = LicenseKeyRingFactory.fromJson('''
          {"keys":[{
            "key_id":"issuer-2026-01",
            "public_key_base64url":"$_publicKey",
            "status":"$status"
          }]}
        ''');
        expect(ring['issuer-2026-01']!.status.name, status);
      }
    });

    test('rejects unknown root and issuer key fields', () {
      expect(
        () => LicenseKeyRingFactory.fromJson(
          '{"keys":[],"private_key":"must-not-be-accepted"}',
        ),
        throwsFormatException,
      );
      expect(
        () => LicenseKeyRingFactory.fromJson('''
          {"keys":[{
            "key_id":"issuer-2026-01",
            "public_key_base64url":"$_publicKey",
            "status":"active",
            "private_key":"must-not-be-accepted"
          }]}
        '''),
        throwsFormatException,
      );
    });

    test('rejects malformed public key encodings and unknown statuses', () {
      for (final value in ['', 'not-base64url', 'AAAAAAAAAAAAAAAA']) {
        expect(
          () => LicenseKeyRingFactory.fromJson('''
            {"keys":[{
              "key_id":"issuer-2026-01",
              "public_key_base64url":"$value",
              "status":"active"
            }]}
          '''),
          throwsFormatException,
        );
      }

      expect(
        () => LicenseKeyRingFactory.fromJson('''
          {"keys":[{
            "key_id":"issuer-2026-01",
            "public_key_base64url":"$_publicKey",
            "status":"enabled"
          }]}
        '''),
        throwsFormatException,
      );
    });

    test('rejects duplicate issuer IDs and malformed identifiers', () {
      expect(
        () => LicenseKeyRingFactory.fromJson('''
          {"keys":[
            {"key_id":"issuer-2026-01","public_key_base64url":"$_publicKey","status":"active"},
            {"key_id":"issuer-2026-01","public_key_base64url":"$_publicKey","status":"standby"}
          ]}
        '''),
        throwsArgumentError,
      );
      expect(
        () => LicenseKeyRingFactory.fromJson('''
          {"keys":[{
            "key_id":"bad issuer id",
            "public_key_base64url":"$_publicKey",
            "status":"active"
          }]}
        '''),
        throwsArgumentError,
      );
    });

    test('malformed build-time configuration falls back to an empty ring', () {
      final ring = LicenseKeyRingFactory.fromEnvironment(
        serialized: '{"keys": "not-an-array"}',
      );

      expect(ring.keyIds, isEmpty);
    });

    test('rejects malformed JSON and non-array keys', () {
      expect(
        () => LicenseKeyRingFactory.fromJson('{'),
        throwsFormatException,
      );
      expect(
        () => LicenseKeyRingFactory.fromJson('{"keys":{}}'),
        throwsFormatException,
      );
    });
  });
}
