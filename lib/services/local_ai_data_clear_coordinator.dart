import '../data/database_helper.dart';
import 'ai_trace_runtime.dart';
import 'local_ai_attachment_store.dart';
import 'local_ai_service.dart';

/// Coordinates deletion of AI-owned data domains.
///
/// Trace recording is stopped and flushed before the trace file is removed.
/// Native runtime release must succeed before deleting attachments that may
/// still be held by an in-flight inference. Independent domains are still
/// attempted after a failure, and every skipped domain is reported explicitly.
class LocalAiDataClearCoordinator {
  LocalAiDataClearCoordinator({
    required Future<bool> Function() stopTraceRecording,
    required Future<void> Function(bool wasEnabled) resumeTraceRecording,
    required Future<LocalAiRuntimeCacheClearResult> Function()
        clearRuntimeCache,
    required Future<void> Function() clearAttachments,
    required Future<void> Function() clearTrace,
    required Future<void> Function() clearDatabase,
  })  : _stopTraceRecording = stopTraceRecording,
        _clearRuntimeCache = clearRuntimeCache,
        _clearAttachments = clearAttachments,
        _clearTrace = clearTrace,
        _clearDatabase = clearDatabase;

  /// Production wiring. The caller must pass the same recorder and writer
  /// instances used by the AI workflow so stop/flush/clear share their queues.
  factory LocalAiDataClearCoordinator.forApp() {
    return LocalAiDataClearCoordinator(
      stopTraceRecording: AiTraceRuntime.recorder.disableAndFlush,
      resumeTraceRecording: (wasEnabled) async {
        if (wasEnabled) AiTraceRuntime.recorder.enable();
      },
      clearRuntimeCache: LocalAiService().clearRuntimeCache,
      clearAttachments: LocalAiAttachmentStore().clearAll,
      clearTrace: AiTraceRuntime.writer.clear,
      clearDatabase: DatabaseHelper.instance.clearAllAiConversationData,
    );
  }

  final Future<bool> Function() _stopTraceRecording;
  final Future<void> Function(bool wasEnabled) _resumeTraceRecording;
  final Future<LocalAiRuntimeCacheClearResult> Function() _clearRuntimeCache;
  final Future<void> Function() _clearAttachments;
  final Future<void> Function() _clearTrace;
  final Future<void> Function() _clearDatabase;

  Future<LocalAiDataClearResult>? _inFlight;

  /// Concurrent taps share one operation; they cannot race two destructive
  /// cleanup sequences or report a second run as independently completed.
  Future<LocalAiDataClearResult> clearAll() {
    final active = _inFlight;
    if (active != null) return active;

    late final Future<LocalAiDataClearResult> tracked;
    tracked = _clear().whenComplete(() {
      if (identical(_inFlight, tracked)) _inFlight = null;
    });
    _inFlight = tracked;
    return tracked;
  }

  Future<LocalAiDataClearResult> _clear() async {
    var traceRecordingStopped = false;
    var traceWasEnabled = false;
    String? traceStopErrorCode;
    try {
      traceWasEnabled = await _stopTraceRecording();
      traceRecordingStopped = true;
    } catch (_) {
      traceStopErrorCode = 'TRACE_STOP_FAILED';
    }

    LocalAiRuntimeCacheClearResult runtime;
    try {
      runtime = await _clearRuntimeCache();
    } catch (_) {
      runtime = const LocalAiRuntimeCacheClearResult(
        runtimeReleased: false,
        cacheDeleted: false,
        modelFileExists: false,
        errorCode: 'NATIVE_CLEAR_CALL_FAILED',
      );
    }

    var attachmentsCleared = false;
    String? attachmentErrorCode;
    if (!runtime.runtimeReleased) {
      attachmentErrorCode = 'SKIPPED_NATIVE_RELEASE_FAILED';
    } else {
      try {
        await _clearAttachments();
        attachmentsCleared = true;
      } catch (_) {
        attachmentErrorCode = 'ATTACHMENT_CLEAR_FAILED';
      }
    }

    var traceCleared = false;
    String? traceErrorCode;
    if (!traceRecordingStopped) {
      traceErrorCode = 'SKIPPED_TRACE_STOP_FAILED';
    } else {
      try {
        await _clearTrace();
        traceCleared = true;
      } catch (_) {
        traceErrorCode = 'TRACE_CLEAR_FAILED';
      }
    }

    var databaseCleared = false;
    String? databaseErrorCode;
    try {
      await _clearDatabase();
      databaseCleared = true;
    } catch (_) {
      databaseErrorCode = 'DATABASE_CLEAR_FAILED';
    }

    var traceRecordingResumed = false;
    String? traceResumeErrorCode;
    if (traceRecordingStopped) {
      try {
        await _resumeTraceRecording(traceWasEnabled);
        traceRecordingResumed = true;
      } catch (_) {
        traceResumeErrorCode = 'TRACE_RESUME_FAILED';
      }
    }

    return LocalAiDataClearResult(
      traceRecordingStopped: traceRecordingStopped,
      traceRecordingResumed: traceRecordingResumed,
      traceStopErrorCode: traceStopErrorCode,
      traceResumeErrorCode: traceResumeErrorCode,
      runtime: runtime,
      attachmentsCleared: attachmentsCleared,
      attachmentErrorCode: attachmentErrorCode,
      traceCleared: traceCleared,
      traceErrorCode: traceErrorCode,
      databaseCleared: databaseCleared,
      databaseErrorCode: databaseErrorCode,
    );
  }
}

class LocalAiDataClearResult {
  const LocalAiDataClearResult({
    required this.traceRecordingStopped,
    required this.traceRecordingResumed,
    required this.runtime,
    required this.attachmentsCleared,
    required this.traceCleared,
    required this.databaseCleared,
    this.traceStopErrorCode,
    this.traceResumeErrorCode,
    this.attachmentErrorCode,
    this.traceErrorCode,
    this.databaseErrorCode,
  });

  final bool traceRecordingStopped;
  final bool traceRecordingResumed;
  final String? traceStopErrorCode;
  final String? traceResumeErrorCode;
  final LocalAiRuntimeCacheClearResult runtime;
  final bool attachmentsCleared;
  final String? attachmentErrorCode;
  final bool traceCleared;
  final String? traceErrorCode;
  final bool databaseCleared;
  final String? databaseErrorCode;

  bool get complete =>
      traceRecordingStopped &&
      traceRecordingResumed &&
      runtime.complete &&
      attachmentsCleared &&
      traceCleared &&
      databaseCleared;

  /// null means the Native method call failed, so model retention is unknown.
  bool? get installedModelRetained =>
      runtime.errorCode == 'NATIVE_CLEAR_CALL_FAILED'
          ? null
          : runtime.modelFileExists;

  List<String> get failedDomains => [
        if (!traceRecordingStopped) 'trace_recording_stop',
        if (traceRecordingStopped && !traceRecordingResumed)
          'trace_recording_resume',
        if (!runtime.runtimeReleased) 'native_runtime_release',
        if (!runtime.cacheDeleted) 'native_runtime_cache',
        if (!attachmentsCleared) 'attachments',
        if (!traceCleared) 'trace',
        if (!databaseCleared) 'conversation_database',
      ];
}
