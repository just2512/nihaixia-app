import 'package:flutter/services.dart';

const yanjiLicenseChannelName = 'com.nihaisha.nihaisha_app/licensing';

class LicensePlatformFailure implements Exception {
  const LicensePlatformFailure(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'LicensePlatformFailure($code: $message)';
}

class DeviceKeyInfo {
  const DeviceKeyInfo({
    required this.spkiDerBase64Url,
    required this.sha256Base64Url,
    required this.securityLevel,
    this.strongBoxFallback = false,
  });

  final String spkiDerBase64Url;
  final String sha256Base64Url;

  /// Client-reported security level; informational only, never remote proof.
  final String securityLevel;

  /// True only when StrongBox was explicitly unavailable and TEE fallback used.
  final bool strongBoxFallback;
}

abstract interface class LicensePlatform {
  /// Returns null when no active Token file exists. This operation is get-only.
  Future<String?> readActiveToken();

  /// Replaces the complete Token only after the caller has verified it.
  Future<void> writeActiveTokenAtomically(String token);

  /// Deletes only the local Token file; never deletes the device key.
  Future<void> deleteActiveToken();

  /// Get-only: never generates a missing device key.
  Future<DeviceKeyInfo> getDeviceKey();

  /// Explicit activation action only. Existing aliases must never be replaced.
  Future<DeviceKeyInfo> createDeviceKeyForActivation();

  /// Signs the original YANJIR1 payload segment with the existing device key.
  Future<String> signActivationRequest(String payloadBase64Url);

  /// Local challenge sign + verify using the existing private key only.
  Future<DeviceKeyInfo> checkPrivateKeyUsability();
}

class MethodChannelLicensePlatform implements LicensePlatform {
  MethodChannelLicensePlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(yanjiLicenseChannelName);

  final MethodChannel _channel;

  Future<Map<String, Object?>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      if (result == null) {
        throw LicensePlatformFailure('emptyPlatformResult', method);
      }
      return result;
    } on PlatformException catch (error) {
      throw LicensePlatformFailure(error.code, error.message);
    } on MissingPluginException {
      throw const LicensePlatformFailure('platformUnavailable');
    }
  }

  Future<void> _invokeConfirmed(
    String method, [
    Map<String, Object?>? arguments,
    required String confirmationField,
  ]) async {
    final response = await _invokeMap(method, arguments);
    if (response[confirmationField] != true) {
      throw LicensePlatformFailure(
        'invalidPlatformResponse',
        '$method did not confirm $confirmationField=true',
      );
    }
  }

  @override
  Future<String?> readActiveToken() async {
    final response = await _invokeMap('readLicenseToken');
    final token = response['token'];
    if (token == null) return null;
    if (token is! String || token.isEmpty) {
      throw const LicensePlatformFailure('storeCorrupt');
    }
    return token;
  }

  @override
  Future<void> writeActiveTokenAtomically(String token) async {
    await _invokeConfirmed(
      'writeLicenseTokenAfterVerification',
      {'token': token},
      confirmationField: 'stored',
    );
  }

  @override
  Future<void> deleteActiveToken() async {
    await _invokeConfirmed(
      'deleteLicenseToken',
      confirmationField: 'deleted',
    );
  }

  @override
  Future<DeviceKeyInfo> getDeviceKey() async =>
      _deviceKeyFromMap(await _invokeMap('getDeviceKey'));

  @override
  Future<DeviceKeyInfo> createDeviceKeyForActivation() async =>
      _deviceKeyFromMap(
        await _invokeMap('createDeviceKeyForActivation'),
      );

  @override
  Future<String> signActivationRequest(String payloadBase64Url) async {
    final response = await _invokeMap(
      'signActivationRequest',
      {'payloadBase64Url': payloadBase64Url},
    );
    final signature = response['signatureBase64Url'];
    if (signature is! String || signature.isEmpty) {
      throw const LicensePlatformFailure('invalidPlatformResponse');
    }
    return signature;
  }

  @override
  Future<DeviceKeyInfo> checkPrivateKeyUsability() async =>
      _deviceKeyFromMap(await _invokeMap('checkPrivateKeyUsability'));

  static DeviceKeyInfo _deviceKeyFromMap(Map<String, Object?> value) {
    final spki = value['publicKeySpkiBase64Url'];
    final fingerprint = value['publicKeySha256'];
    final level = value['securityLevel'];
    final fallback = value['strongBoxFallback'];
    if (spki is! String ||
        spki.isEmpty ||
        fingerprint is! String ||
        fingerprint.isEmpty ||
        level is! String ||
        level.isEmpty ||
        (fallback != null && fallback is! bool)) {
      throw const LicensePlatformFailure('invalidDeviceKeyResponse');
    }
    return DeviceKeyInfo(
      spkiDerBase64Url: spki,
      sha256Base64Url: fingerprint,
      securityLevel: level,
      strongBoxFallback: fallback == true,
    );
  }
}
