import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ai_credential_vault.dart';

void main() {
  group('AiCredentialVault', () {
    late _MemoryCredentialStorage storage;
    late AiCredentialVault vault;

    setUp(() {
      storage = _MemoryCredentialStorage();
      vault = AiCredentialVault(
        storage: storage,
        platform: TargetPlatform.android,
        random: Random(41),
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
      final collisionVault = AiCredentialVault(
        storage: storage,
        platform: TargetPlatform.android,
        random: _ConstantRandom(),
      );
      const original = 'original-secret';
      await collisionVault.createCredential(original);

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
    });

    test('rejects platforms without an explicitly supported secure store',
        () {
      expect(
        () => AiCredentialVault(
          storage: storage,
          platform: TargetPlatform.linux,
          random: Random(41),
        ),
        throwsA(isA<AiCredentialVaultUnsupportedPlatformException>()),
      );
      expect(
        () => AiCredentialVault(
          storage: storage,
          platform: TargetPlatform.iOS,
          random: Random(41),
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

  @override
  Future<String?> read({required String key}) async {
    readCalls++;
    final failure = readFailure;
    if (failure != null) throw failure;
    return values[key];
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

class _ConstantRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
