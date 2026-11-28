import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/native_files_io.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('app-temp-cache-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('generic cache cleanup preserves AI-owned runtime and attachment folders', () async {
    final runtimeCache = Directory('${tempDirectory.path}/litertlm');
    final runtimeNested = Directory('${runtimeCache.path}/nested');
    final aiAttachments = Directory('${tempDirectory.path}/local_ai_attachments');
    final ordinaryNested = Directory('${tempDirectory.path}/image_picker');
    await runtimeNested.create(recursive: true);
    await aiAttachments.create(recursive: true);
    await ordinaryNested.create(recursive: true);

    final runtimeFile = File('${runtimeNested.path}/mapped.bin');
    final attachmentFile = File('${aiAttachments.path}/picked.jpg');
    final ordinaryFile = File('${ordinaryNested.path}/stale.tmp');
    final unrelatedNestedRuntimeName =
        File('${tempDirectory.path}/other/litertlm/stale.tmp');
    await unrelatedNestedRuntimeName.parent.create(recursive: true);
    await runtimeFile.writeAsBytes([1, 2, 3, 4]);
    await attachmentFile.writeAsBytes([5, 6, 7]);
    await ordinaryFile.writeAsBytes([8, 9]);
    await unrelatedNestedRuntimeName.writeAsBytes([10]);

    final removedBytes = await clearTempCacheBytes(
      directoryProvider: () async => tempDirectory,
    );

    expect(removedBytes, 3);
    expect(await runtimeFile.exists(), isTrue);
    expect(await attachmentFile.exists(), isTrue);
    expect(await ordinaryFile.exists(), isFalse);
    expect(await unrelatedNestedRuntimeName.exists(), isFalse);
    expect(await runtimeCache.exists(), isTrue);
    expect(await aiAttachments.exists(), isTrue);
  });

  test('generic cache cleanup is idempotent and reports only deletable files', () async {
    final runtimeCache = Directory('${tempDirectory.path}/litertlm');
    await runtimeCache.create();
    await File('${runtimeCache.path}/runtime.bin').writeAsBytes([1, 2, 3]);

    final first = await clearTempCacheBytes(
      directoryProvider: () async => tempDirectory,
    );
    final second = await clearTempCacheBytes(
      directoryProvider: () async => tempDirectory,
    );

    expect(first, 0);
    expect(second, 0);
    expect(await File('${runtimeCache.path}/runtime.bin').exists(), isTrue);
  });
}
