import 'package:flutter/services.dart';

const aiCredentialVaultChannelName =
    'com.nihaisha.app/ai_credential_vault';

/// Decrypted only for the lifetime of a real model request. The caller must
/// compare [providerId] with the selected ProviderConfig before using [secret].
class AiCredentialVaultEntry {
  const AiCredentialVaultEntry({
    required this.providerId,
    required this.secret,
  });

  final String providerId;
  final String secret;
}

abstract interface class AiCredentialVault {
  /// Stores a provider secret and returns an opaque reference.
  ///
  /// Implementations must never persist the secret in SQLite, preferences,
  /// logs, exported model configuration or backup-visible files.
  Future<String> save({
    required String providerId,
    required String secret,
  });

  /// Returns null only when the reference has no stored credential. The
  /// returned providerId must be checked against the selected ProviderConfig.
  Future<AiCredentialVaultEntry?> read(String credentialRef);

  Future<void> delete(String credentialRef);

  /// Checks local storage only. This method must never perform a network call.
  Future<bool> exists(String credentialRef);
}

class AiCredentialVaultException implements Exception {
  const AiCredentialVaultException(this.code);

  final String code;

  @override
  String toString() => 'AiCredentialVaultException($code)';
}

class MethodChannelAiCredentialVault implements AiCredentialVault {
  MethodChannelAiCredentialVault({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(aiCredentialVaultChannelName);

  final MethodChannel _channel;

  @override
  Future<String> save({
    required String providerId,
    required String secret,
  }) async {
    if (providerId.trim().isEmpty ||
        providerId != providerId.trim() ||
        secret.isEmpty) {
      throw const AiCredentialVaultException('CREDENTIAL_INPUT_INVALID');
    }
    final response = await _invokeMap(
      'save',
      <String, Object?>{'providerId': providerId, 'secret': secret},
    );
    final credentialRef = response?['credentialRef'];
    if (credentialRef is! String || credentialRef.isEmpty) {
      throw const AiCredentialVaultException('CREDENTIAL_RESPONSE_INVALID');
    }
    return credentialRef;
  }

  @override
  Future<AiCredentialVaultEntry?> read(String credentialRef) async {
    _validateReference(credentialRef);
    final response = await _invokeMap(
      'read',
      <String, Object?>{'credentialRef': credentialRef},
    );
    if (response?['found'] == false) return null;
    final providerId = response?['providerId'];
    final secret = response?['secret'];
    if (response?['found'] != true ||
        providerId is! String ||
        providerId.isEmpty ||
        secret is! String ||
        secret.isEmpty) {
      throw const AiCredentialVaultException('CREDENTIAL_RESPONSE_INVALID');
    }
    return AiCredentialVaultEntry(providerId: providerId, secret: secret);
  }

  @override
  Future<void> delete(String credentialRef) async {
    _validateReference(credentialRef);
    final response = await _invokeMap(
      'delete',
      <String, Object?>{'credentialRef': credentialRef},
    );
    if (response?['deleted'] is! bool) {
      throw const AiCredentialVaultException('CREDENTIAL_RESPONSE_INVALID');
    }
  }

  @override
  Future<bool> exists(String credentialRef) async {
    _validateReference(credentialRef);
    final response = await _invokeMap(
      'exists',
      <String, Object?>{'credentialRef': credentialRef},
    );
    final exists = response?['exists'];
    if (exists is! bool) {
      throw const AiCredentialVaultException('CREDENTIAL_RESPONSE_INVALID');
    }
    return exists;
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
    } on PlatformException catch (error) {
      throw AiCredentialVaultException(error.code);
    } on MissingPluginException {
      // Unsupported platforms, including Web in the current release, fail
      // closed rather than writing a secret to an insecure fallback.
      throw const AiCredentialVaultException(
        'CREDENTIAL_VAULT_UNAVAILABLE',
      );
    }
  }

  void _validateReference(String value) {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (!uuid.hasMatch(value)) {
      throw const AiCredentialVaultException(
        'CREDENTIAL_REFERENCE_INVALID',
      );
    }
  }
}
