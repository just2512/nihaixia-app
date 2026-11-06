/// Native temporary-file cleanup used by the app's local cache management.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Clear temporary files and return the number of bytes removed.
Future<int> clearTempCacheBytes() async {
  final tempDir = await getTemporaryDirectory();
  int totalSize = 0;
  if (await tempDir.exists()) {
    final files = tempDir.listSync(recursive: true);
    for (final file in files) {
      if (file is File) totalSize += await file.length();
    }
    for (final file in files) {
      try {
        if (file is File) await file.delete();
      } catch (_) {}
    }
  }
  return totalSize;
}
