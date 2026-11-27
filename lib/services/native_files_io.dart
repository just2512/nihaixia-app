/// Native temporary-file cleanup used by the app's local cache management.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Clear temporary files and return the number of bytes removed.
Future<int> clearTempCacheBytes({
  Future<Directory> Function()? directoryProvider,
}) async {
  final tempDir = await (directoryProvider ?? getTemporaryDirectory)();
  int totalSize = 0;
  if (await tempDir.exists()) {
    final protectedDirectories = [
      p.join(tempDir.path, 'litertlm'),
      p.join(tempDir.path, 'local_ai_attachments'),
    ].map(p.normalize).toList(growable: false);
    final files = tempDir
        .listSync(recursive: true, followLinks: false)
        .where((entity) {
          final path = p.normalize(entity.path);
          return !protectedDirectories.any((protectedPath) =>
              path == protectedPath || p.isWithin(protectedPath, path));
        })
        .toList(growable: false);
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
