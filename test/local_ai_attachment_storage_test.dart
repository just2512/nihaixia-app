import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:nihaisha_app/services/local_ai_attachment_storage.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalAiAttachmentStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-ai-attachments-',
    );
    storage = LocalAiAttachmentStorage(
      temporaryDirectoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('adopts picker files into the dedicated AI directory', () async {
    final source = File('${temporaryDirectory.path}/picker_photo.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);

    final adopted = await storage.adoptPickerFile(
      source.path,
      kind: 'image',
    );

    expect(await File(adopted).exists(), isTrue);
    expect(p.basename(p.dirname(adopted)), LocalAiAttachmentStorage.directoryName);
    expect(await File(adopted).readAsBytes(), [1, 2, 3, 4]);
    expect(await source.exists(), isFalse);
  });

  test('clear removes AI attachments but preserves unrelated cache files', () async {
    final managedPath = await storage.createPath(
      kind: 'audio',
      extension: 'wav',
    );
    await File(managedPath).writeAsBytes([1, 2, 3]);
    final unrelated = File('${temporaryDirectory.path}/other_feature.bin');
    await unrelated.writeAsBytes([9, 8, 7]);

    expect(await storage.clear(), 1);
    expect(await File(managedPath).exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('rejects a symlinked AI attachment root without touching its target', () async {
    final outside = await Directory.systemTemp.createTemp(
      'nihaisha-ai-attachments-outside-',
    );
    try {
      final sentinel = File('${outside.path}/keep.bin');
      await sentinel.writeAsBytes([7, 7, 7]);
      final link = Link(
        p.join(temporaryDirectory.path, LocalAiAttachmentStorage.directoryName),
      );
      await link.create(outside.path);

      await expectLater(storage.createPath(kind: 'image', extension: 'jpg'),
          throwsA(isA<FileSystemException>()));
      await expectLater(
        storage.clear(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsBytes(), [7, 7, 7]);
      expect(await link.exists(), isTrue);
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test('legacy cleanup deletes only known local AI recording names', () async {
    final legacy = File('${temporaryDirectory.path}/local_ai_123456.wav');
    final unrelated = File('${temporaryDirectory.path}/voice_123456.wav');
    final unrelatedImage = File('${temporaryDirectory.path}/local_ai_photo.jpg');
    await legacy.writeAsBytes([1]);
    await unrelated.writeAsBytes([2]);
    await unrelatedImage.writeAsBytes([3]);

    expect(await storage.clearLegacyRecordings(), 1);
    expect(await legacy.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
    expect(await unrelatedImage.exists(), isTrue);
  });
}
