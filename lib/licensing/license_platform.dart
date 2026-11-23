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
  });

  final String spkiDerBase64Url;
  final String sha256Base64Url;

  /// Client-reported security level; informational only, never remote proof.
  final String securityLevel;
}

abstract interface class LicensePlatform {
  /// Returns null when no active Token file exists.
  Future<String?> readActiveToken();

  /// Atomically replaces the full token file after caller verification.
  Future<void> writeActiveTokenAtomically(String token);

  /// Deletes only the local Token file; never deletes the device key.
  Future<void> deleteActiveToken();

  /// Get-only: never generates a missing device key.
  Future<DeviceKeyInfo> getDeviceKey();

  /// Explicit activation action only. Existing aliases must never be replaced.
  Future<DeviceKeyInfo> createDeviceKeyForActivation();

  /// Local challenge sign + verify using the existing private key only.
  Future<void> checkPrivateKeyUsability();
}

class MethodChannelLicensePlatform implements LicensePlatform {
  MethodChannelLicensePlatform({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(yanjiLicenseChannelName);

  final MethodChannel _channel;

  Future<T> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      final value = await _channel.invokeMethod<T>(method, arguments);
      if (value == null) {
        throw LicensePlatformFailure('EMPTY_PLATFORM_RESULT', method);
      }
      return value;
    } on PlatformException catch (error) {
      throw LicensePlatformFailure(error.code, error.message);
    } on MissingPluginException {
      throw const LicensePlatformFailure('PLATFORM_UNAVAILABLE');
    }
  }

  @override
  Future<String?> readActiveToken() async {
    try {
      return await _channel.invokeMethod<String>('readActiveToken');
    } on PlatformException catch (error) {
      throw LicensePlatformFailure(error.code, error.message);
    } on MissingPluginException {
      throw const LicensePlatformFailure('PLATFORM_UNAVAILABLE');
    }
  }

  @override
  Future<void> _invokeVoid(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw LicensePlatformFailure(error.code, error.message);
    } on MissingPluginException {
      throw const LicensePlatformFailure('PLATFORM_UNAVAILABLE');
    }
  }

  @override
  Future<void> writeActiveTokenAtomically(String token) async {
    await _invokeVoid('writeActiveTokenAtomically', {'token': token});
  }

  @override
  Future<void> deleteActiveToken() async {
    await _invokeVoid('deleteActiveToken');
  }

  @override
  Future<DeviceKeyInfo> getDeviceKey() async =>
      _deviceKeyFromMap(await _invoke<Map<Object?, Object?>>('getDeviceKey'));

  @override
  Future<DeviceKeyInfo> createDeviceKeyForActivation() async =>
      _deviceKeyFromMap(
        await _invoke<Map<Object?, Object?>>('createDeviceKeyForActivation'),
      );

  @override
  Future<void> checkPrivateKeyUsability() async {
    await _invokeVoid('checkPrivateKeyUsability');
  }

  static DeviceKeyInfo _deviceKeyFromMap(Map<Object?, Object?> value) {
    final spki = value['spki_der_base64url'];
    final fingerprint = value['sha256_base64url'];
    final level = value['security_level'];
    if (spki is! String ||
        spki.isEmpty ||
        fingerprint is! String ||
        fingerprint.isEmpty ||
        level is! String ||
        level.isEmpty) {
      throw const LicensePlatformFailure('INVALID_DEVICE_KEY_RESPONSE');
    }
    return DeviceKeyInfo(
      spkiDerBase64Url: spki,
      sha256Base64Url: fingerprint,
      securityLevel: level,
    );
  }
}
