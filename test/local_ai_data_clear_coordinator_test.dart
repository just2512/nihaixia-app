import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_data_clear_coordinator.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

LocalAiRuntimeCacheClearResult nativeResult({
  bool released = true,
  bool deleted = true,
  bool modelExists = true,
  String? errorCode,
}) =>
    LocalAiRuntimeCacheClearResult(
      runtimeReleased: released,
      cacheDeleted: deleted,
      modelFileExists: modelExists,
      errorCode: errorCode,
    );

void main() {
  test('stops trace, releases runtime, clears owned files and database in order', () async {
    final order = <String>[];
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async { order.add('stop-trace'); return true; },
      resumeTraceRecording: (wasEnabled) async { order.add('resume-trace'); expect(wasEnabled, isTrue); },
      clearRuntimeCache: () async {
        order.add('native');
        return nativeResult();
      },
      clearAttachments: () async => order.add('attachments'),
      clearTrace: () async => order.add('trace'),
      clearDatabase: () async => order.add('database'),
    );

    final result = await coordinator.clearAll();

    expect(order, ['stop-trace', 'native', 'attachments', 'trace', 'database', 'resume-trace']);
    expect(result.complete, isTrue);
    expect(result.traceRecordingResumed, isTrue);
    expect(result.failedDomains, isEmpty);
    expect(result.installedModelRetained, isTrue);
  });

  test('does not delete attachments while Native runtime release is unconfirmed', () async {
    final order = <String>[];
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async { order.add('stop-trace'); return true; },
      resumeTraceRecording: (wasEnabled) async { order.add('resume-trace'); expect(wasEnabled, isTrue); },
      clearRuntimeCache: () async {
        order.add('native');
        return nativeResult(
          released: false,
          deleted: false,
          errorCode: 'RUNTIME_RELEASE_FAILED',
        );
      },
      clearAttachments: () async => order.add('attachments'),
      clearTrace: () async => order.add('trace'),
      clearDatabase: () async => order.add('database'),
    );

    final result = await coordinator.clearAll();

    expect(order, ['stop-trace', 'native', 'trace', 'database', 'resume-trace']);
    expect(result.complete, isFalse);
    expect(
      result.failedDomains,
      ['native_runtime_release', 'native_runtime_cache', 'attachments'],
    );
    expect(result.attachmentsCleared, isFalse);
    expect(result.attachmentErrorCode, 'SKIPPED_NATIVE_RELEASE_FAILED');
    expect(result.traceCleared, isTrue);
    expect(result.databaseCleared, isTrue);
  });

  test('reports each failed domain and still attempts later safe domains', () async {
    final order = <String>[];
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async { order.add('stop-trace'); return true; },
      resumeTraceRecording: (wasEnabled) async { order.add('resume-trace'); expect(wasEnabled, isTrue); },
      clearRuntimeCache: () async {
        order.add('native');
        return nativeResult();
      },
      clearAttachments: () async {
        order.add('attachments');
        throw StateError('injected attachment failure');
      },
      clearTrace: () async {
        order.add('trace');
        throw StateError('injected trace failure');
      },
      clearDatabase: () async {
        order.add('database');
      },
    );

    final result = await coordinator.clearAll();

    expect(order, ['stop-trace', 'native', 'attachments', 'trace', 'database', 'resume-trace']);
    expect(result.complete, isFalse);
    expect(result.failedDomains, ['attachments', 'trace']);
    expect(result.attachmentErrorCode, 'ATTACHMENT_CLEAR_FAILED');
    expect(result.traceErrorCode, 'TRACE_CLEAR_FAILED');
    expect(result.databaseCleared, isTrue);
  });

  test('does not clear trace when recorder cannot be stopped', () async {
    final order = <String>[];
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async {
        order.add('stop-trace');
        throw StateError('injected recorder stop failure');
      },
      resumeTraceRecording: (wasEnabled) async => order.add('resume-trace'),
      clearRuntimeCache: () async {
        order.add('native');
        return nativeResult();
      },
      clearAttachments: () async => order.add('attachments'),
      clearTrace: () async => order.add('trace'),
      clearDatabase: () async => order.add('database'),
    );

    final result = await coordinator.clearAll();

    expect(order, ['stop-trace', 'native', 'attachments', 'database']);
    expect(result.complete, isFalse);
    expect(result.traceRecordingStopped, isFalse);
    expect(result.traceRecordingResumed, isFalse);
    expect(result.traceStopErrorCode, 'TRACE_STOP_FAILED');
    expect(result.traceErrorCode, 'SKIPPED_TRACE_STOP_FAILED');
    expect(result.failedDomains, ['trace_recording_stop', 'trace']);
    expect(result.databaseCleared, isTrue);
  });

  test('concurrent clear requests share one destructive operation', () async {
    final gate = Completer<LocalAiRuntimeCacheClearResult>();
    var stopCalls = 0;
    var nativeCalls = 0;
    var attachmentCalls = 0;
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async {
        stopCalls++;
        return true;
      },
      resumeTraceRecording: (wasEnabled) async {},
      clearRuntimeCache: () {
        nativeCalls++;
        return gate.future;
      },
      clearAttachments: () async {
        attachmentCalls++;
      },
      clearTrace: () async {},
      clearDatabase: () async {},
    );

    final first = coordinator.clearAll();
    final second = coordinator.clearAll();
    expect(identical(first, second), isTrue);

    gate.complete(nativeResult());
    final results = await Future.wait([first, second]);

    expect(stopCalls, 1);
    expect(nativeCalls, 1);
    expect(attachmentCalls, 1);
    expect(results.first.complete, isTrue);
    expect(identical(results.first, results.last), isTrue);
  });

  test('preserves default-off recorder state after clearing', () async {
    bool? resumedFrom;
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async => false,
      resumeTraceRecording: (wasEnabled) async { resumedFrom = wasEnabled; },
      clearRuntimeCache: () async => nativeResult(),
      clearAttachments: () async {},
      clearTrace: () async {},
      clearDatabase: () async {},
    );
    final result = await coordinator.clearAll();
    expect(resumedFrom, isFalse);
    expect(result.traceRecordingStopped, isTrue);
    expect(result.traceRecordingResumed, isTrue);
    expect(result.complete, isTrue);
  });

  test('native method call exception makes model retention UNKNOWN', () async {
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async => true,
      resumeTraceRecording: (wasEnabled) async {},
      clearRuntimeCache: () async => throw StateError('channel unavailable'),
      clearAttachments: () async {},
      clearTrace: () async {},
      clearDatabase: () async {},
    );

    final result = await coordinator.clearAll();

    expect(result.complete, isFalse);
    expect(result.traceRecordingResumed, isTrue);
    expect(result.runtime.errorCode, 'NATIVE_CLEAR_CALL_FAILED');
    expect(result.failedDomains, [
      'native_runtime_release',
      'native_runtime_cache',
      'attachments',
    ]);
    expect(result.installedModelRetained, isNull);
    expect(result.attachmentsCleared, isFalse);
    expect(result.traceCleared, isTrue);
    expect(result.databaseCleared, isTrue);
  });

  test('reports recorder resume failure and does not claim clear complete', () async {
    final coordinator = LocalAiDataClearCoordinator(
      stopTraceRecording: () async => true,
      resumeTraceRecording: (wasEnabled) async { throw StateError('injected recorder resume failure'); },
      clearRuntimeCache: () async => nativeResult(),
      clearAttachments: () async {},
      clearTrace: () async {},
      clearDatabase: () async {},
    );
    final result = await coordinator.clearAll();
    expect(result.traceRecordingStopped, isTrue);
    expect(result.traceRecordingResumed, isFalse);
    expect(result.traceResumeErrorCode, 'TRACE_RESUME_FAILED');
    expect(result.failedDomains, ['trace_recording_resume']);
    expect(result.complete, isFalse);
  });
}
