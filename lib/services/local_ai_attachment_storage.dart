import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores local-AI attachments in one app-owned cache directory so orphaned
/// files can be enumerated and cleared without deleting unrelated cache data.
class LocalAiAttachmentStorage {
  LocalAiAttachmentStorage({
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectoryProvider;
  int _sequence = 0;

  static const directoryName = 'local_ai_attachments';

  Future<Directory> getDirectory() => _ownedDirectory(create: true);

  Future<Directory> _ownedDirectory({bool create = false}) async {
    final temporaryRoot = await _temporaryDirectoryProvider();
    final canonicalRoot = p.normalize(
      await temporaryRoot.resolveSymbolicLinks(),
    );
    final directoryPath = p.join(canonicalRoot, directoryName);
    final type = await FileSystemEntity.type(
      directoryPath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'AI attachment directory must not be a symbolic link',
        directoryPath,
      );
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'AI attachment path is not a directory',
        directoryPath,
      );
    }

    final directory = Directory(directoryPath);
    if (create && type == FileSystemEntityType.notFound) {
      await directory.create();
    }
    if (await directory.exists()) {
      final resolvedPath = p.normalize(await directory.resolveSymbolicLinks());
      if (resolvedPath != directoryPath ||
          p.dirname(resolvedPath) != canonicalRoot) {
        throw FileSystemException(
          'AI attachment directory escapes the temporary root',
          directoryPath,
        );
      }
    }
    return directory;
  }

  Future<String> createPath({
    required String kind,
    required String extension,
  }) async {
    final normalizedKind = kind.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final normalizedExtension =
        extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (normalizedKind.isEmpty || normalizedExtension.isEmpty) {
      throw ArgumentError('Attachment kind and extension are required');
    }
    final directory = await getDirectory();
    _sequence++;
    final filename =
        '${normalizedKind}_${DateTime.now().microsecondsSinceEpoch}_$_sequence.$normalizedExtension';
    return p.join(directory.path, filename);
  }

  /// Copies a picker-owned temporary file into the AI-only directory, then
  /// removes the original only when it is inside the app temporary root.
  Future<String> adoptPickerFile(
    String sourcePath, {
    required String kind,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('AI attachment does not exist', sourcePath);
    }
    final targetPath = await createPath(
      kind: kind,
      extension: p.extension(sourcePath).replaceFirst('.', ''),
    );
    final target = await source.copy(targetPath);
    if (await target.length() <= 0) {
      await target.delete();
      throw FileSystemException('AI attachment is empty', targetPath);
    }

    final temporaryRoot =
        p.normalize((await _temporaryDirectoryProvider()).absolute.path);
    final normalizedSource = p.normalize(source.absolute.path);
    final normalizedTarget = p.normalize(target.absolute.path);
    if (p.isWithin(temporaryRoot, normalizedSource) &&
        normalizedSource != normalizedTarget) {
      try {
        await source.delete();
      } catch (_) {
        // The managed copy is authoritative; stale picker cleanup is retried
        // by the caller's normal attachment cleanup path.
      }
    }
    return target.path;
  }

  Future<int> clear() async {
    final directory = await _ownedDirectory();
    if (!await directory.exists()) return 0;
    return _deleteOwnedTree(directory);
  }

  Future<int> _deleteOwnedTree(Directory directory) async {
    var deletedFiles = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Link) {
        // Delete the link itself; never traverse its target.
        await entity.delete();
      } else if (entity is Directory) {
        deletedFiles += await _deleteOwnedTree(entity);
      } else if (entity is File) {
        await entity.delete();
        deletedFiles++;
      }
    }
    await directory.delete();
    return deletedFiles;
  }

  /// Compatibility cleanup for recordings created before the dedicated
  /// directory existed. It intentionally does not scan or delete all cache.
  Future<int> clearLegacyRecordings() async {
    final root = await _temporaryDirectoryProvider();
    var deleted = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!RegExp(r'^local_ai_\d+\.wav$').hasMatch(p.basename(entity.path))) {
        continue;
      }
      await entity.delete();
      deleted++;
    }
    return deleted;
  }
}
