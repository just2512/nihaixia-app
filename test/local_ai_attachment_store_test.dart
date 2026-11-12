import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_attachment_store.dart';

void main() {
  late Directory root;
  late Directory sharedTemp;
  late LocalAiAttachmentStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-ai-attachment-store-');
    sharedTemp = Directory('${root.path}/shared-temp');
    await sharedTemp.create();
    store = LocalAiAttachmentStore(
      directoryProvider: () async => root,
      random: Random(7),
      clock: () => DateTime.utc(2026, 11, 12),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('imports picked files into an isolated AI-owned directory', () async {
    final source = File('${sharedTemp.path}/picked-image.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);

    final importedPath = await store.importFile(source.path);

    expect(importedPath, startsWith('${root.path}/${LocalAiAttachmentStore.directoryName}/'));
    expect(await File(importedPath).readAsBytes(), [1, 2, 3, 4]);
    expect(await source.exists(), isTrue);
    expect(await store.listOwnedFiles(), hasLength(1));
  });

  test('creates unique recording paths under the AI-owned directory', () async {
    final first = await store.createRecordingPath();
    final second = await store.createRecordingPath();

    expect(first, isNot(second));
    expect(first, startsWith('${root.path}/${LocalAiAttachmentStore.directoryName}/'));
    expect(first, endsWith('.wav'));
  });

  test('rejects recording extensions containing path components', () async {
    await expectLater(
      store.createRecordingPath(extension: '../outside'),
      throwsArgumentError,
    );
  });

  test('clearAll deletes owned attachments but leaves shared temp files', () async {
    final source = File('${sharedTemp.path}/shared.jpg');
    await source.writeAsBytes([9, 8, 7]);
    final importedPath = await store.importFile(source.path);
    final recordingPath = await store.createRecordingPath();
    await File(recordingPath).writeAsBytes([5, 4, 3]);

    await store.clearAll();

    expect(await File(importedPath).exists(), isFalse);
    expect(await File(recordingPath).exists(), isFalse);
    expect(await source.exists(), isTrue);
    expect(await store.listOwnedFiles(), isEmpty);
  });

  test('clearAll is idempotent when no owned directory exists', () async {
    await store.clearAll();
    await store.clearAll();

    expect(await store.listOwnedFiles(), isEmpty);
  });
}
