import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_attachment_store.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalAiAttachmentStore store;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('local-ai-attachment-store-');
    store = LocalAiAttachmentStore(
      temporaryDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('creates unique recording paths under the dedicated AI directory', () async {
    final first = await store.createAudioRecordingPath();
    final second = await store.createAudioRecordingPath();

    expect(first, isNot(equals(second)));
    expect(first, contains('/${LocalAiAttachmentStore.directoryName}/audio_'));
    expect(first, endsWith('/recording.wav'));
    expect(pDirectory(first), isTrue);
  });

  test('imports image bytes into an app-owned directory without modifying source',
      () async {
    final source = File('${temporaryDirectory.path}/picker-image.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);

    final managedPath = await store.importImage(source.path);

    expect(await File(managedPath).readAsBytes(), [1, 2, 3, 4]);
    expect(await source.exists(), isTrue);
    expect(managedPath, contains('/${LocalAiAttachmentStore.directoryName}/image_'));
  });

  test('deletes only owned files and leaves files outside the AI directory', () async {
    final source = File('${temporaryDirectory.path}/keep.txt');
    await source.writeAsString('keep');
    final audioPath = await store.createAudioRecordingPath();
    await File(audioPath).writeAsString('synthetic audio');

    await store.deleteOwnedPaths([source.path, audioPath]);

    expect(await source.readAsString(), 'keep');
    expect(await File(audioPath).exists(), isFalse);
  });

  test('clearAll removes AI attachments but preserves shared temp files', () async {
    final sentinel = File('${temporaryDirectory.path}/other-plugin-cache.bin');
    await sentinel.writeAsBytes([9, 8, 7]);
    final imageSource = File('${temporaryDirectory.path}/image.png');
    await imageSource.writeAsBytes([1, 2, 3]);
    final managedImage = await store.importImage(imageSource.path);
    final audioPath = await store.createAudioRecordingPath();
    await File(audioPath).writeAsBytes([4, 5, 6]);

    await store.clearAll();

    expect(await File(managedImage).exists(), isFalse);
    expect(await File(audioPath).exists(), isFalse);
    expect(await sentinel.readAsBytes(), [9, 8, 7]);
    expect(await imageSource.exists(), isTrue);
  });

  test('rejects a missing picker file and malformed extension', () async {
    await expectLater(
      store.importImage('${temporaryDirectory.path}/missing.jpg'),
      throwsA(isA<FileSystemException>()),
    );
    final source = File('${temporaryDirectory.path}/bad.extension-too-long');
    await source.writeAsBytes([1]);
    await expectLater(
      store.importImage(source.path),
      throwsA(isA<ArgumentError>()),
    );
  });
}

bool pDirectory(String path) =>
    path.contains('/${LocalAiAttachmentStore.directoryName}/audio_');
