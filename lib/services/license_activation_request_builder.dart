import 'dart:convert';
import 'dart:math';

import '../licensing/license_platform.dart';
import '../licensing/license_verifier.dart';

class LicenseActivationRequest {
  const LicenseActivationRequest({
    required this.code,
    required this.requestId,
    required this.deviceFingerprint,
    required this.securityLevel,
    required this.strongBoxFallback,
  });

  final String code;
  final String requestId;
  final String deviceFingerprint;
  final String securityLevel;
  final bool strongBoxFallback;
}

/// Builds the customer-facing YANJIR1 device request.
///
/// Device-key creation is an explicit user action. An existing key is read
/// get-only and reused; this builder never replaces an alias.
class LicenseActivationRequestBuilder {
  LicenseActivationRequestBuilder._();

  static Future<LicenseActivationRequest> create({
    required LicensePlatform platform,
    DateTime Function()? clock,
    Random? random,
  }) async {
    final rng = random ?? Random.secure();
    final key = await _loadOrCreateForExplicitActivation(platform);
    if (!_isCanonicalSha256Base64Url(key.sha256Base64Url)) {
      throw const FormatException('设备公钥指纹格式无效，未生成激活申请。');
    }
    if (key.spkiDerBase64Url.isEmpty || key.securityLevel.isEmpty) {
      throw const FormatException('设备公钥信息不完整，未生成激活申请。');
    }

    final requestId = _uuidV4(rng);
    final nonce = List<int>.generate(32, (_) => rng.nextInt(256));
    final payload = <String, Object?>{
      'schema_version': 1,
      'request_id': requestId,
      'request_nonce': base64UrlEncode(nonce).replaceAll('=', ''),
      'app_id': 'com.nihaisha.nihaisha_app',
      'product_id': 'yanji_pro_lifetime',
      'issued_at': (clock?.call() ?? DateTime.now()).toUtc().toIso8601String(),
      'device_public_key_spki': key.spkiDerBase64Url,
      'device_key_sha256': key.sha256Base64Url,
      'device_key_security_level': key.securityLevel,
    };
    final payloadBytes = LicenseVerifier.canonicalJsonBytes(payload);
    final payloadSegment = base64UrlEncode(payloadBytes).replaceAll('=', '');
    final signature = await platform.signActivationRequest(payloadSegment);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(signature)) {
      throw const FormatException('设备签名格式无效，未生成激活申请。');
    }

    return LicenseActivationRequest(
      code: 'YANJIR1.$payloadSegment.$signature',
      requestId: requestId,
      deviceFingerprint: key.sha256Base64Url,
      securityLevel: key.securityLevel,
      strongBoxFallback: key.strongBoxFallback,
    );
  }

  static Future<DeviceKeyInfo> _loadOrCreateForExplicitActivation(
    LicensePlatform platform,
  ) async {
    try {
      return await platform.getDeviceKey();
    } on LicensePlatformFailure catch (error) {
      if (error.code != 'keyMissing' && error.code != 'KEY_MISSING') {
        rethrow;
      }
    }

    try {
      return await platform.createDeviceKeyForActivation();
    } on LicensePlatformFailure catch (error) {
      // A concurrent explicit activation may create the alias after the
      // get-only check. Re-read that same alias; never create a replacement.
      if (error.code != 'keyAlreadyExists' &&
          error.code != 'KEY_ALREADY_EXISTS') {
        rethrow;
      }
      return platform.getDeviceKey();
    }
  }

  static bool _isCanonicalSha256Base64Url(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
    try {
      final padded = value.padRight(
        value.length + ((4 - value.length % 4) % 4),
        '=',
      );
      final decoded = base64Url.decode(padded);
      return decoded.length == 32 &&
          base64UrlEncode(decoded).replaceAll('=', '') == value;
    } on FormatException {
      return false;
    }
  }

  static String _uuidV4(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
