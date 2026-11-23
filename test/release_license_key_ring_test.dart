import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/licensing/release_license_key_ring.dart';

String _encodedKey(int fill) =>
    base64UrlEncode(List<int>.filled(32, fill)).replaceAll('=', '');

String _configuration(
  List<Map<String, Object?>> keys,
) =>
    jsonEncode({
      'schema_version': 1,
      'keys': keys,
    });

Map<String, Object?> _key(
  String id, {
  required int fill,
  String status = 'active',
}) =>
    {
      'issuer_key_id': id,
      'public_key_base64url': _encodedKey(fill),
      'status': status,
    };

Future<Map<String, dynamic>> _testVectors() async =>
    jsonDecode(
      await File('test/fixtures/pro-license-test-vectors.json').readAsString(),
    ) as Map<String, dynamic>;

void main() {
  group('ReleaseLicenseKeyRingFactory', () {
    test('Debug/Test permits an empty ring but Release does not', () {
      expect(
        ReleaseLicenseKeyRingFactory.fromJson(
          '',
          requireProductionTrustAnchor: false,
        ).keyIds,
        isEmpty,
      );
      expect(
        () => ReleaseLicenseKeyRingFactory.fromJson(
          '',
          requireProductionTrustAnchor: true,
        ),
        throwsStateError,
      );
    });

    test('Release accepts only production issuer ID format', () {
      expect(
        () => ReleaseLicenseKeyRingFactory.fromJson(
          _configuration([
            _key('test-issuer-01', fill: 1),
          ]),
          requireProductionTrustAnchor: true,
        ),
        throwsFormatException,
      );
      expect(
        () => ReleaseLicenseKeyRingFactory.fromJson(
          _configuration([
            _key('issuer-2026-01', fill: 1),
          ]),
          requireProductionTrustAnchor: true,
        ),
        returnsNormally,
      );
    });

    test('active, standby and retired keys may verify; revoked keys may not',
        () {
      final ring = ReleaseLicenseKeyRingFactory.fromJson(
        _configuration([
          _key('issuer-2026-01', fill: 1, status: 'active'),
          _key('issuer-2026-02', fill: 2, status: 'standby'),
          _key('issuer-2025-12', fill: 3, status: 'retired'),
          _key('issuer-2024-06', fill: 4, status: 'revoked'),
          _key('issuer-2024-07', fill: 5, status: 'compromised'),
        ]),
        requireProductionTrustAnchor: true,
      );

      expect(ring.keyIds, hasLength(5));
      expect(ring['issuer-2026-01']!.mayVerify, isTrue);
      expect(ring['issuer-2026-02']!.mayVerify, isTrue);
      expect(ring['issuer-2025-12']!.mayVerify, isTrue);
      expect(ring['issuer-2024-06']!.mayVerify, isFalse);
      expect(ring['issuer-2024-07']!.mayVerify, isFalse);
    });

    test('revoked or compromised entries cannot be the only trust anchors',
        () {
      for (final status in ['revoked', 'compromised']) {
        expect(
          () => ReleaseLicenseKeyRingFactory.fromJson(
            _configuration([
              _key('issuer-2026-01', fill: 1, status: status),
            ]),
            requireProductionTrustAnchor: true,
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects invalid key bytes, duplicate IDs and unknown fields', () {
      final invalidKey = {
        'issuer_key_id': 'issuer-2026-01',
        'public_key_base64url': base64UrlEncode([1, 2, 3]).replaceAll('=', ''),
        'status': 'active',
      };
      expect(
        () => ReleaseLicenseKeyRingFactory.fromJson(
          _configuration([invalidKey]),
          requireProductionTrustAnchor: true,
        ),
        throwsFormatException,
      );
      expect(
        () => ReleaseLicenseKeyRingFactory.fromJson(
          _configuration([
            _key('issuer-2026-01', fill: 1),
            _key('issuer-2026-01', fill: 2, status: 'standby'),
          ]),
          requireProductionTrustAnchor: true,
        ),
        throwsFormatException,
      );
      expect(
        () => ReleaseLicenseKeyRingFactory.fromJson(
          jsonEncode({
            'schema_version': 1,
            'keys': [_key('issuer-2026-01', fill: 1)..['private_key'] = 'forbidden'],
          }),
          requireProductionTrustAnchor: true,
        ),
        throwsFormatException,
      );
    });

    test('the Release factory returns unknownIssuer for the test issuer token',
        () async {
      final vectors = await _testVectors();
      final validLicense = vectors['valid_license'] as Map<String, dynamic>;
      final payload = validLicense['payload'] as Map<String, dynamic>;
      final releaseRing = ReleaseLicenseKeyRingFactory.fromJson(
        _configuration([
          _key('issuer-2026-01', fill: 9),
        ]),
        requireProductionTrustAnchor: true,
      );
      final result = await LicenseVerifier(keyRing: releaseRing).verify(
        validLicense['token'] as String,
        expectedDevicePublicKeySha256:
            payload['device_public_key_sha256'] as String,
      );

      expect(vectors['issuer_key_id'], 'test-issuer-01');
      expect(result.status, LicenseVerificationStatus.unknownIssuer);
    });

    test('test issuer public key is absent from production Dart sources',
        () async {
      final vectors = await _testVectors();
      final rawBase64Url =
          vectors['issuer_public_key_raw_base64url'] as String;
      final bytes = base64Url.decode(
        rawBase64Url.padRight(
          rawBase64Url.length + ((4 - rawBase64Url.length % 4) % 4),
          '=',
        ),
      );
      final encodedStandard = base64Encode(bytes);
      final encodedHex = bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      final sources = [
        File('lib/main.dart'),
        File('lib/licensing/release_license_key_ring.dart'),
      ];
      for (final file in sources) {
        final source = await file.readAsString();
        expect(source, isNot(contains(rawBase64Url)), reason: file.path);
        expect(source, isNot(contains(encodedStandard)), reason: file.path);
        expect(source.toLowerCase(), isNot(contains(encodedHex)),
            reason: file.path);
        expect(source, isNot(contains('test-issuer-01')), reason: file.path);
      }
    });
  });
}
