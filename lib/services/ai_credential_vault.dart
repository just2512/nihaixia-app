import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Operations performed against the platform-backed credential store.
enum AiCredentialVaultOperation { read, write, delete }

/// Platform-neutral storage seam. Production uses [FlutterSecureStorage];
/// tests can provide an in-memory implementation without touching platform
/// channels.
@visibleForTesting
abstract interface class AiCredentialVaultStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

/// Base exception for credential-vault failures.
///
/// Exception messages contain stable error codes only. Platform exceptions
/// are deliberately not retained because their messages are not a safe
/// channel for secret values.
class AiCredentialVaultException implements Exception {
  const AiCredentialVaultException(this.code);

  final String code;

  @override
  String toString() => 'AiCredentialVaultException($code)';
}

class AiCredentialVaultInvalidReferenceException
    extends AiCredentialVaultException {
  const AiCredentialVaultInvalidReferenceException()
      : super('AI_CREDENTIAL_REFERENCE_INVALID');
}

class AiCredentialVaultUnknownReferenceException
    extends AiCredentialVaultException {
  const AiCredentialVaultUnknownReferenceException()
      : super('AI_CREDENTIAL_REFERENCE_UNKNOWN');
}

class AiCredentialVaultEmptySecretException
    extends AiCredentialVaultException {
  const AiCredentialVaultEmptySecretException()
      : super('AI_CREDENTIAL_SECRET_EMPTY');
}

class AiCredentialVaultInvalidStoredValueException
    extends AiCredentialVaultException {
  const AiCredentialVaultInvalidStoredValueException()
      : super('AI_CREDENTIAL_STORED_VALUE_INVALID');
}

class AiCredentialVaultReferenceCollisionException
    extends AiCredentialVaultException {
  const AiCredentialVaultReferenceCollisionException()
      : super('AI_CREDENTIAL_REFERENCE_COLLISION');
}

class AiCredentialVaultUnsupportedPlatformException
    extends AiCredentialVaultException {
  const AiCredentialVaultUnsupportedPlatformException()
      : super('AI_CREDENTIAL_PLATFORM_UNSUPPORTED');
}

class AiCredentialVaultStorageException extends AiCredentialVaultException {
  const AiCredentialVaultStorageException(this.operation)
      : super('AI_CREDENTIAL_STORAGE_OPERATION_FAILED');

  final AiCredentialVaultOperation operation;
}

/// Stores provider secrets outside SQLite and returns only opaque references.
///
/// Supported runtime platforms are Android and Windows. Unsupported
/// platforms, including web, fail closed. Android uses a dedicated plugin
/// namespace and disables the plugin's destructive reset-on-error behavior;
/// Windows delegates key protection to the plugin's Windows implementation.
class AiCredentialVault()
    : this._(
        platform: defaultTargetPlatform,
        isWeb: kIsWeb,
      );

  /// Test-only factory for injecting a deterministic storage seam.
  ///
  /// Production call sites must use [AiCredentialVault.new], which always
  /// selects the platform secure-storage implementation.
  @visibleForTesting
  AiCredentialVault.forTesting({
    required AiCredentialVaultStorage storage,
    required TargetPlatform platform,
    bool isWeb = false,
  }) : this._(
          storage: storage,
          platform: platform,
          isWeb: isWeb,
        );

  AiCredentialVault._({
    AiCredentialVaultStorage? storage,
    required TargetPlatform platform,
    required bool isWeb,
  })  : _platform = platform,
        _storage = storage ??
            _createDefaultStorage(
              platform,
              isWeb: isWeb,
            ) {
    if (isWeb || !_isSupportedPlatform(_platform)) {
      throw const AiCredentialVaultUnsupportedPlatformException();
    }
  }

  static const String _referencePrefix = 'aicred:v1:';
  static const String _storageKeyPrefix = 'ai_credential_v1_';
  static const String _androidStorageNamespace =
      'nihaixia_ai_credentials_v1';
  static const int _referenceEntropyBytes = 32;
  static const int _maxReferenceAttempts = 8;

  static final RegExp _referencePattern =
      RegExp(r'^aicred:v1:[A-Za-z0-9_-]{43}$');

  final TargetPlatform _platform;
  final Random _random = Random.secure();
  final AiCredentialVaultStorage _storage;

  /// Persists [secret] and returns its opaque, versioned reference.
  ///
  /// The secret is never returned, included in the reference, or included in
  /// an exception message. Empty and whitespace-only values are rejected.
  Future<String> createCredential(String secret) async {
    _validateSecret(secret);

    for (var attempt = 0; attempt < _maxReferenceAttempts; attempt++) {
      final reference = _newReference();
      final key = _storageKeyFor(reference);

      String? existing;
      try {
        existing = await _storage.read(key: key);
      } catch (_) {
        throw const AiCredentialVaultStorageException(
          AiCredentialVaultOperation.read,
        );
      }
      if (existing != null) continue;

      try {
        await _storage.write(key: key, value: secret);
        return reference;
      } catch (_) {
        throw const AiCredentialVaultStorageException(
          AiCredentialVaultOperation.write,
        );
      }
    }

    throw const AiCredentialVaultReferenceCollisionException();
  }

  /// Reads a secret by reference. Unknown or malformed references fail closed.
  Future<String> readCredential(String reference) async {
    final key = _storageKeyFor(reference);
    final value = await _readStoredValue(key);
    if (value == null) {
      throw const AiCredentialVaultUnknownReferenceException();
    }
    if (value.trim().isEmpty) {
      throw const AiCredentialVaultInvalidStoredValueException();
    }
    return value;
  }

  /// Replaces the value behind an existing reference.
  ///
  /// The reference remains unchanged, so the provider configuration does not
  /// need a database update. This is an explicit overwrite operation; it is
  /// not an automatic retry or provider-switch policy.
  Future<void> replaceCredential(String reference, String newSecret) async {
    _validateSecret(newSecret);
    final key = _storageKeyFor(reference);
    final existing = await _readStoredValue(key);
    if (existing == null) {
      throw const AiCredentialVaultUnknownReferenceException();
    }

    try {
      await _storage.write(key: key, value: newSecret);
    } catch (_) {
      throw const AiCredentialVaultStorageException(
        AiCredentialVaultOperation.write,
      );
    }
  }

  /// Deletes an existing secret. Unknown references are not treated as
  /// successful deletes.
  Future<void> deleteCredential(String reference) async {
    final key = _storageKeyFor(reference);
    final existing = await _readStoredValue(key);
    if (existing == null) {
      throw const AiCredentialVaultUnknownReferenceException();
    }

    try {
      await _storage.delete(key: key);
    } catch (_) {
      throw const AiCredentialVaultStorageException(
        AiCredentialVaultOperation.delete,
      );
    }
  }

  String _newReference() {
    final bytes = List<int>.generate(
      _referenceEntropyBytes,
      (_) => _random.nextInt(256),
      growable: false,
    );
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    return '$_referencePrefix$encoded';
  }

  String _storageKeyFor(String reference) {
    if (!_referencePattern.hasMatch(reference)) {
      throw const AiCredentialVaultInvalidReferenceException();
    }
    return '$_storageKeyPrefix${reference.substring(_referencePrefix.length)}';
  }

  Future<String?> _readStoredValue(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      throw const AiCredentialVaultStorageException(
        AiCredentialVaultOperation.read,
      );
    }
  }

  void _validateSecret(String secret) {
    if (secret.trim().isEmpty) {
      throw const AiCredentialVaultEmptySecretException();
    }
  }

  static bool _isSupportedPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.windows;

  static AiCredentialVaultStorage _createDefaultStorage(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb || !_isSupportedPlatform(platform)) {
      throw const AiCredentialVaultUnsupportedPlatformException();
    }
    return const _FlutterSecureStorageAdapter();
  }
}

class _FlutterSecureStorageAdapter implements AiCredentialVaultStorage {
  const _FlutterSecureStorageAdapter()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(
            storageNamespace: AiCredentialVault._androidStorageNamespace,
            resetOnError: false,
          ),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
