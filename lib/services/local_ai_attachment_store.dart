import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns only AI attachments under a dedicated child of the app temp directory.
/// It never recursively clears the shared temp directory.
class LocalAiAttachmentStore {
  LocalAiAttachmentStore({
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  static const directoryName = 'local_ai_attachments';

  final Future<Directory> Function() _temporaryDirectoryProvider;

  Future<Directory> _ensureRoot() async {
    final temporary = await _temporaryDirectoryProvider();
    final root = Directory(p.join(temporary.path, directoryName));
    final existingType = await FileSystemEntity.type(root.path, followLinks: false);
    if (existingType == FileSystemEntityType.link) {
      throw StateError('AI attachment directory must not be a symbolic link');
    }
    await root.create(recursive: true);
    final canonicalTemporary = await temporary.resolveSymbolicLinks();
    final canonicalRoot = await root.resolveSymbolicLinks();
    if (p.dirname(canonicalRoot) != canonicalTemporary) {
      throw StateError('AI attachment directory escaped the app temp directory');
    }
    return Directory(canonicalRoot);
  }

  Future<Directory?> _existingRoot() async {
    final temporary = await _temporaryDirectoryProvider();
    final root = Directory(p.join(temporary.path, directoryName));
    if (!await root.exists()) return null;
    final canonicalTemporary = await temporary.resolveSymbolicLinks();
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError('AI attachment directory must not be a symbolic link');
    }
    final canonicalRoot = await root.resolveSymbolicLinks();
    if (p.dirname(canonicalRoot) != canonicalTemporary) {
      throw StateError('AI attachment directory escaped the app temp directory');
    }
    return Directory(canonicalRoot);
  }

  /// Returns a unique app-owned WAV path; the recorder creates the file.
  Future<String> createAudioRecordingPath() async {
    final root = await _ensureRoot();
    final directory = await root.createTemp('audio_');
    return p.join(directory.path, 'recording.wav');
  }

  /// Copies a validated image-picker file into the AI-owned directory.
  /// The caller remains responsible for deleting the picker-owned source.
  Future<String> importImage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Image attachment does not exist', sourcePath);
    }
    final extension = p.extension(source.path).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'Unsupported image extension');
    }

    final root = await _ensureRoot();
    final directory = await root.createTemp('image_');
    final destination = File(p.join(directory.path, 'attachment$extension'));
    try {
      await source.copy(destination.path);
      return destination.path;
    } catch (_) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Deletes only exact files lexically inside the AI-owned directory.
  /// Symlinks are removed as links and are never followed to external targets.
  Future<void> deleteOwnedPaths(Iterable<String?> paths) async {
    final root = await _existingRoot();
    if (root == null) return;
    final rootPath = p.normalize(root.absolute.path);

    for (final rawPath in paths.whereType<String>().where((value) => value.isNotEmpty)) {
      final file = File(rawPath);
      final lexicalPath = p.normalize(file.absolute.path);
      if (!p.isWithin(rootPath, lexicalPath)) continue;

      final type = await FileSystemEntity.type(lexicalPath, followLinks: false);
      if (type == FileSystemEntityType.file || type == FileSystemEntityType.link) {
        await file.delete();
      }

      final parent = Directory(p.dirname(lexicalPath));
      if (p.equals(parent.path, rootPath) || !await parent.exists()) continue;
      if (await parent.list().isEmpty) {
        await parent.delete();
      }
    }
  }

  /// Removes the dedicated AI attachment root only.
  Future<void> clearAll() async {
    final root = await _existingRoot();
    if (root == null) return;
    await root.delete(recursive: true);
  }
}
