import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ai_credential_vault.dart';

void main() {
  group('AiCredentialVault', () {
    late _MemoryCredentialStorage storage;
    late AiCredentialVault vault;

    setUp(() {
      storage = _MemoryCredentialStorage();
      vault = AiCredentialVault.forTesting(
        storage: storage,
        platform: TargetPlatform.android,
      );
    });

    test('creates an opaque reference and reads the stored secret', () async {
      const secret = 'provider-secret-do-not-expose';
      final reference = await vault.createCredential(secret);

      expect(reference, matches(RegExp(r'^aicred:v1:[A-Za-z0-9_-]{43}$')));
      expect(reference, isNot(contains(secret)));
      expect(await vault.readCredential(reference), secret);
      expect(storage.values, hasLength(1));
      expect(storage.values.values.single, secret);
    });

    test('uses distinct random references for different credentials',
        () async {
      final first = await vault.createCredential('first-secret');
      final second = await vault.createCredential('second-secret');

      expect(first, isNot(second));
      expect(storage.values, hasLength(2));
    });

    test('rejects empty and whitespace-only secrets', () async {
      await expectLater(
        vault.createCredential(''),
        throwsA(isA<AiCredentialVaultEmptySecretException>()),
      );
      await expectLater(
        vault.createCredential(' \t\n '),
        throwsA(isA<AiCredentialVaultEmptySecretException>()),
      );
      expect(storage.values, isEmpty);
    });

    test('rejects malformed references before touching storage', () async {
      await expectLater(
        vault.readCredential('../plaintext'),
        throwsA(isA<AiCredentialVaultInvalidReferenceException>()),
      );
      await expectLater(
        vault.replaceCredential('credential-ref-1', 'replacement-secret'),
        throwsA(isA<AiCredentialVaultInvalidReferenceException>()),
      );
      await expectLater(
        vault.deleteCredential('credential-ref-1'),
        throwsA(isA<AiCredentialVaultInvalidReferenceException>()),
      );
      await expectLater(
        vault.exists('../plaintext'),
        throwsA(isA<AiCredentialVaultInvalidReferenceException>()),
      );
      expect(storage.readCalls, 0);
    });

    test('fails closed for a syntactically valid but unknown reference',
        () async {
      final unknown = _referenceForAllZeroBytes();

      await expectLater(
        vault.readCredential(unknown),
        throwsA(isA<AiCredentialVaultUnknownReferenceException>()),
      );
      await expectLater(
        vault.replaceCredential(unknown, 'replacement-secret'),
        throwsA(isA<AiCredentialVaultUnknownReferenceException>()),
      );
      await expectLater(
        vault.deleteCredential(unknown),
        throwsA(isA<AiCredentialVaultUnknownReferenceException>()),
      );
    });

    test('delete removes the value and subsequent reads fail closed',
        () async {
      final reference = await vault.createCredential('secret-to-delete');

      await vault.deleteCredential(reference);

      expect(storage.values, isEmpty);
      await expectLater(
        vault.readCredential(reference),
        throwsA(isA<AiCredentialVaultUnknownReferenceException>()),
      );
    });

    test('checks reference existence without returning the secret', () async {
      const secret = 'existence-check-secret-must-stay-private';
      final reference = await vault.createCredential(secret);
      final readsBeforeCheck = storage.readCalls;

      expect(await vault.exists(reference), isTrue);
      expect(await vault.exists(_referenceForAllZeroBytes()), isFalse);
      expect(storage.readCalls, readsBeforeCheck + 2);
      expect(storage.values.values, contains(secret));
    });

    test('replacement rotates the value without changing its reference',
        () async {
      const original = 'old-provider-secret';
      const replacement = 'new-provider-secret';
      final reference = await vault.createCredential(original);

      await vault.replaceCredential(reference, replacement);

      expect(await vault.readCredential(reference), replacement);
      expect(storage.values.values, contains(replacement));
      expect(storage.values.values, isNot(contains(original)));
      expect(storage.values, hasLength(1));
    });

    test('reports failed replacement without exposing the attempted secret',
        () async {
      const original = 'still-active-secret';
      const replacement = 'replacement-secret-marker';
      final reference = await vault.createCredential(original);
      storage.writeFailure = StateError(replacement);

      final error = await _captureException(
        () => vault.replaceCredential(reference, replacement),
      );

      expect(error, isA<AiCredentialVaultStorageException>());
      expect(
        (error as AiCredentialVaultStorageException).operation,
        AiCredentialVaultOperation.write,
      );
      expect(error.toString(), isNot(contains(replacement)));
      // The fake backend models a rejected pre-commit write. This does not
      // claim that every platform provider offers transactional writes.
      expect(await vault.readCredential(reference), original);
    });

    test('does not overwrite an existing random reference on collision',
        () async {
      final collisionVault = AiCredentialVault.forTesting(
        storage: storage,
        platform: TargetPlatform.android,
      );
      const original = 'original-secret';
      await collisionVault.createCredential(original);
      storage.occupyMissingKeys = true;

      await expectLater(
        collisionVault.createCredential('must-not-overwrite'),
        throwsA(isA<AiCredentialVaultReferenceCollisionException>()),
      );
      expect(storage.values.values.single, original);
    });

    test('wraps read, write and delete failures in typed safe errors',
        () async {
      const marker = 'secret-must-never-appear-in-errors';
      storage.writeFailure = StateError(marker);

      final writeError = await _captureException(
        () => vault.createCredential(marker),
      );
      expect(writeError, isA<AiCredentialVaultStorageException>());
      expect(
        (writeError as AiCredentialVaultStorageException).operation,
        AiCredentialVaultOperation.write,
      );
      expect(writeError.toString(), isNot(contains(marker)));

      storage.writeFailure = null;
      final reference = await vault.createCredential(marker);

      storage.readFailure = StateError(marker);
      final readError = await _captureException(
        () => vault.readCredential(reference),
      );
      expect(readError, isA<AiCredentialVaultStorageException>());
      expect(
        (readError as AiCredentialVaultStorageException).operation,
        AiCredentialVaultOperation.read,
      );
      expect(readError.toString(), isNot(contains(marker)));
      final existsError = await _captureException(
        () => vault.exists(reference),
      );
      expect(existsError, isA<AiCredentialVaultStorageException>());
      expect(
        (existsError as AiCredentialVaultStorageException).operation,
        AiCredentialVaultOperation.read,
      );
      expect(existsError.toString(), isNot(contains(marker)));

      storage.readFailure = null;
      storage.deleteFailure = StateError(marker);
      final deleteError = await _captureException(
        () => vault.deleteCredential(reference),
      );
      expect(deleteError, isA<AiCredentialVaultStorageException>());
      expect(
        (deleteError as AiCredentialVaultStorageException).operation,
        AiCredentialVaultOperation.delete,
      );
      expect(deleteError.toString(), isNot(contains(marker)));
    });

    test('does not accept an empty stored value as a successful read',
        () async {
      const reference = 'aicred:v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final key = _storageKey(reference);
      storage.values[key] = '';

      await expectLater(
        vault.readCredential(reference),
        throwsA(isA<AiCredentialVaultInvalidStoredValueException>()),
      );
      await expectLater(
        vault.exists(reference),
        throwsA(isA<AiCredentialVaultInvalidStoredValueException>()),
      );
    });

    test('serializes storage operations across Vault instances', () async {
      final concurrentStorage = _ConcurrencyTrackingStorage();
      final secondVault = AiCredentialVault.forTesting(
        storage: concurrentStorage,
        platform: TargetPlatform.windows,
      );
      final firstVault = AiCredentialVault.forTesting(
        storage: concurrentStorage,
        platform: TargetPlatform.android,
      );

      final references = await Future.wait(<Future<String>>[
        firstVault.createCredential('first-secret'),
        secondVault.createCredential('second-secret'),
        firstVault.createCredential('third-secret'),
      ]);

      expect(references.toSet(), hasLength(3));
      expect(concurrentStorage.maxConcurrentOperations, 1);
      expect(concurrentStorage.values, hasLength(3));
    });

    test('excludes namespaced secure storage files from Android backups', () {
      const secureStoragePreferences = <String>[
        'nihaixia_ai_credentials_v1.xml',
        'FlutterSecureKeyStorage:nihaixia_ai_credentials_v1.xml',
        'FlutterSecureStorageConfiguration:nihaixia_ai_credentials_v1.xml',
      ];
      final fullBackupRules = File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsStringSync();
      final extractionRules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      final cloudBackupRules = extractionRules
          .split('<cloud-backup>')
          .last
          .split('</cloud-backup>')
          .first;
      final deviceTransferRules = extractionRules
          .split('<device-transfer>')
          .last
          .split('</device-transfer>')
          .first;

      for (final preferenceFile in secureStoragePreferences) {
        final exclusion =
            '<exclude domain="sharedpref" path="$preferenceFile" />';
        expect(fullBackupRules, contains(exclusion));
        expect(cloudBackupRules, contains(exclusion));
        expect(deviceTransferRules, contains(exclusion));
      }

      for (final existingExclusion in <String>[
        'ai_models/',
        'ai_trace.jsonl',
        'ai_trace.jsonl.tmp',
      ]) {
        expect(fullBackupRules, contains('path="$existingExclusion"'));
        expect(extractionRules, contains('path="$existingExclusion"'));
      }
    });

    test('rejects platforms without an explicitly supported secure store',
        () {
      expect(
        () => AiCredentialVault.forTesting(
          storage: storage,
          platform: TargetPlatform.linux,
        ),
        throwsA(isA<AiCredentialVaultUnsupportedPlatformException>()),
      );
      expect(
        () => AiCredentialVault.forTesting(
          storage: storage,
          platform: TargetPlatform.iOS,
        ),
        throwsA(isA<AiCredentialVaultUnsupportedPlatformException>()),
      );
    });
  });
}

Future<Object> _captureException<T>(Future<T> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  throw StateError('Expected the operation to fail.');
}

String _referenceForAllZeroBytes() =>
    'aicred:v1:${base64Url.encode(List<int>.filled(32, 0)).replaceAll('=', '')}';

String _storageKey(String reference) =>
    'ai_credential_v1_${reference.substring('aicred:v1:'.length)}';

class _MemoryCredentialStorage implements AiCredentialVaultStorage {
  final Map<String, String> values = <String, String>{};

  Object? readFailure;
  Object? writeFailure;
  Object? deleteFailure;
  int readCalls = 0;
  bool occupyMissingKeys = false;

  @override
  Future<String?> read({required String key}) async {
    readCalls++;
    final failure = readFailure;
    if (failure != null) throw failure;
    return values[key] ?? (occupyMissingKeys ? 'occupied' : null);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    final failure = deleteFailure;
    if (failure != null) throw failure;
    values.remove(key);
  }
}

class _ConcurrencyTrackingStorage implements AiCredentialVaultStorage {
  final Map<String, String> values = <String, String>{};
  int activeOperations = 0;
  int maxConcurrentOperations = 0;

  Future<T> _track<T>(Future<T> Function() operation) async {
    activeOperations++;
    if (activeOperations > maxConcurrentOperations) {
      maxConcurrentOperations = activeOperations;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return await operation();
    } finally {
      activeOperations--;
    }
  }

  @override
  Future<String?> read({required String key}) =>
      _track(() async => values[key]);

  @override
  Future<void> write({required String key, required String value}) =>
      _track(() async {
        values[key] = value;
      });

  @override
  Future<void> delete({required String key}) =>
      _track(() async {
        values.remove(key);
      });
}
