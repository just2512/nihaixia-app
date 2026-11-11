import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_trace.dart';

/// Local-only bounded persistence for allowlisted AI trace metadata.
///
/// This writer is not enabled or wired into production by itself. The caller
/// must explicitly opt in by passing it to [AiTraceRecorder] with enabled=true.
/// No user text, prompts, model responses, symptoms, attachment paths, or
/// identity data are accepted by [AiTraceEvent.toJson].
class LocalAiTraceFileWriter {
  LocalAiTraceFileWriter({
    Future<Directory> Function()? directoryProvider,
    DateTime Function()? clock,
    this.maxEvents = 500,
    this.retention = const Duration(days: 7),
  })  : _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now {
    if (maxEvents < 1) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'Must be positive');
    }
    if (retention <= Duration.zero) {
      throw ArgumentError.value(retention, 'retention', 'Must be positive');
    }
  }

  final Future<Directory> Function() _directoryProvider;
  final DateTime Function() _clock;
  final int maxEvents;
  final Duration retention;

  Future<void> _queue = Future<void>.value();

  String get fileName => 'ai_trace.jsonl';

  /// Callable writer accepted by AiTraceRecorder.
  Future<void> call(AiTraceEvent event) {
    final next = _queue.then((_) => _write(event));
    // Keep the queue usable after a failed disk write. The original caller
    // still receives [next] and can observe the failure.
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _write(AiTraceEvent event) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));

    final now = _clock().toUtc();
    final cutoff = now.subtract(retention);
    final retained = <Map<String, Object?>>[];

    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) continue;
          final timestamp = DateTime.tryParse(
            decoded['occurred_at'] as String? ?? '',
          );
          if (timestamp == null || timestamp.toUtc().isBefore(cutoff)) {
            continue;
          }
          retained.add(Map<String, Object?>.from(decoded));
        } on FormatException {
          // A partial/corrupt line is discarded; it must not block tracing.
        } on TypeError {
          // Invalid field types are discarded rather than trusted.
        }
      }
    }

    retained.add(event.toJson());
    final bounded = retained.length > maxEvents
        ? retained.sublist(retained.length - maxEvents)
        : retained;
    final content = bounded.map(jsonEncode).join('\n');

    // Serialize to a temporary file before replacing the current snapshot.
    // The delete/rename pair has a small crash window; the recorder is
    // best-effort and a missing trace file must never affect AI execution.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      content.isEmpty ? '' : '$content\n',
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  /// Deletes only this writer's file and its temporary replacement.
  Future<void> clear() {
    final next = _queue.then((_) => _clear());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _clear() async {
    final directory = await _directoryProvider();
    final file = File(p.join(directory.path, fileName));
    final temporary = File('${file.path}.tmp');
    if (await file.exists()) await file.delete();
    if (await temporary.exists()) await temporary.delete();
  }
}
