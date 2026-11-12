import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns only files copied or created for the local AI conversation workflow.
///
/// Files are kept in a dedicated app-private directory. Cleanup additionally
/// recognizes one exact legacy recording filename pattern at the temp root;
/// it never recursively scans or deletes generic shared-temp files.
class LocalAiAttachmentStore {
  LocalAiAttachmentStore({
    Future<Directory> Function()? directoryProvider,
    Random? random,
    DateTime Function()? clock,
  })  : _directoryProvider = directoryProvider ?? getTemporaryDirectory,
        _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directoryProvider;
  final Random _random;
  final DateTime Function() _clock;

  static const directoryName = 'local_ai_attachments';

  Future<Directory> _ownedDirectory() async {
    final support = await _directoryProvider();
    return Directory(p.join(support.path, directoryName));
  }

  /// Copies an image or other picked attachment into the AI-owned directory.
  /// The source is never deleted because it may belong to another subsystem.
  Future<String> importFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'AI attachment source does not exist',
        sourcePath,
      );
    }
    final extension = p.extension(source.path).toLowerCase();
    final directory = await _ownedDirectory();
    await directory.create(recursive: true);
    final destination = File(
      p.join(directory.path, _newFileName(extension)),
    );
    return (await source.copy(destination.path)).path;
  }

  /// Reserves a unique path for a recorder that writes directly to a file.
  /// Only a simple file extension is accepted; path components are rejected.
  Future<String> createRecordingPath({String extension = '.wav'}) async {
    if (!RegExp(r'^\.[a-zA-Z0-9]{1,8}$').hasMatch(extension)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Invalid file extension',
      );
    }
    final directory = await _ownedDirectory();
    await directory.create(recursive: true);
    return p.join(directory.path, _newFileName(extension.toLowerCase()));
  }

  String _newFileName(String extension) {
    final nonce = List<int>.generate(8, (_) => _random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'attachment_${_clock().microsecondsSinceEpoch}_$nonce$extension';
  }

  /// Deletes direct children of this dedicated directory plus only the exact
  /// legacy recording filename allowlist at the temp root. It never recurses
  /// into shared temp subdirectories or touches model files/other app data.
  Future<void> clearAll() async {
    final directory = await _ownedDirectory();
    if (await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        await entity.delete();
      }
      await directory.delete();
    }

    // Older releases wrote recordings directly into the shared temp root as
    // local_ai_<millisecondsSinceEpoch>.wav. Delete only that exact pattern.
    final tempRoot = await _directoryProvider();
    if (!await tempRoot.exists()) return;
    final legacyRecordingName = RegExp(r'^local_ai_[0-9]+[.]wav$');
    await for (final entity in tempRoot.list(followLinks: false)) {
      if (entity is File &&
          legacyRecordingName.hasMatch(p.basename(entity.path))) {
        await entity.delete();
      }
    }
  }

  Future<List<File>> listOwnedFiles() async {
    final directory = await _ownedDirectory();
    if (!await directory.exists()) return const <File>[];
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    return List<File>.unmodifiable(files);
  }
}
