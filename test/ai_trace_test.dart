import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ai_trace.dart';

void main() {
  group('AiTraceRecorder', () {
    test('is disabled by default and performs no ID generation or writes', () async {
      var ids = 0;
      var writes = 0;
      final recorder = AiTraceRecorder(
        writer: (_) async => writes++,
        idFactory: () {
          ids++;
          return 'trace';
        },
      );

      final context = recorder.start(stage: AiTraceStage.input);
      await recorder.record(
        context,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
      );

      expect(context.enabled, isFalse);
      expect(context.traceId, isNull);
      expect(ids, 0);
      expect(writes, 0);
    });

    test('uses one trace ID and emits NOT_STARTED then terminal metadata', () async {
      final events = <AiTraceEvent>[];
      final times = <DateTime>[
        DateTime.utc(2026, 11, 11, 10),
        DateTime.utc(2026, 11, 11, 10, 0, 1),
      ];
      final recorder = AiTraceRecorder(
        enabled: true,
        writer: (event) async => events.add(event),
        idFactory: () => '0123456789abcdef0123456789abcdef',
        clock: () => times.removeAt(0),
      );

      final context = recorder.start(
        stage: AiTraceStage.input,
        route: 'consultation',
        mode: 'automatic',
      );
      await Future<void>.delayed(Duration.zero);
      await recorder.record(
        context,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.unknown,
        durationMs: -10,
        backend: 'gpu',
        modelVersion: 'local-e4b',
        errorCode: 'NATIVE_TIMEOUT',
      );

      expect(events, hasLength(2));
      expect(events.map((event) => event.traceId).toSet(), {context.traceId});
      expect(events.first.status, AiTraceStatus.notStarted);
      expect(events.last.status, AiTraceStatus.unknown);
      expect(events.last.durationMs, 0);
      expect(events.last.backend, 'gpu');
    });

    test('event JSON contains only allowlisted metadata', () {
      final event = AiTraceEvent(
        traceId: 'trace',
        stage: AiTraceStage.retrieval,
        status: AiTraceStatus.succeeded,
        occurredAt: DateTime.utc(2026, 11, 11),
        sourceIds: ['formula:guizhi_tang'],
      );

      final json = event.toJson();
      expect(json['status'], 'SUCCEEDED');
      expect(json['stage'], 'RETRIEVAL');
      expect(json.keys, containsAll([
        'schema_version',
        'trace_id',
        'stage',
        'status',
        'occurred_at',
        'source_ids',
      ]));
      expect(json.keys, isNot(contains('text')));
      expect(json.keys, isNot(contains('prompt')));
      expect(json.keys, isNot(contains('response')));
      expect(json.keys, isNot(contains('symptoms')));
      expect(json.keys, isNot(contains('attachment_path')));
    });

    test('trace schema exposes required stages and NOT_APPLICABLE status', () {
      expect(AiTraceStatus.notApplicable.wireValue, 'NOT_APPLICABLE');
      expect(AiTraceStage.input.wireValue, 'INPUT');
      expect(AiTraceStage.redFlag.wireValue, 'RED_FLAG');
      expect(AiTraceStage.route.wireValue, 'ROUTE');
      expect(AiTraceStage.entityResolution.wireValue, 'ENTITY_RESOLUTION');
      expect(AiTraceStage.retrieval.wireValue, 'RETRIEVAL');
      expect(AiTraceStage.contextAssembly.wireValue, 'CONTEXT_ASSEMBLY');
      expect(AiTraceStage.modelInput.wireValue, 'MODEL_INPUT');
      expect(AiTraceStage.modelOutput.wireValue, 'MODEL_OUTPUT');
      expect(AiTraceStage.toolExecution.wireValue, 'TOOL_EXECUTION');
      expect(AiTraceStage.argumentValidation.wireValue, 'ARGUMENT_VALIDATION');
      expect(AiTraceStage.businessExecution.wireValue, 'BUSINESS_EXECUTION');
      expect(AiTraceStage.resultValidation.wireValue, 'RESULT_VALIDATION');
      expect(AiTraceStage.finalRender.wireValue, 'FINAL_RENDER');
      expect(AiTraceStage.persistedState.wireValue, 'PERSISTED_STATE');
    });

    test('writer failures do not propagate to the caller', () async {
      final recorder = AiTraceRecorder(
        enabled: true,
        writer: (_) async => throw StateError('storage unavailable'),
        idFactory: () => 'trace',
      );
      final context = recorder.start(stage: AiTraceStage.input);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        recorder.record(
          context,
          stage: AiTraceStage.presentation,
          status: AiTraceStatus.succeeded,
        ),
        completes,
      );
    });

    test('trace ID factory failure does not escape or block the request', () {
      final recorder = AiTraceRecorder(
        enabled: true,
        writer: (_) async {},
        idFactory: () => throw StateError('secure random unavailable'),
      );

      final context = recorder.start(stage: AiTraceStage.input);
      expect(context.enabled, isFalse);
      expect(context.traceId, isNull);
    });

    test('does not create an enabled context without a writer', () {
      var ids = 0;
      final recorder = AiTraceRecorder(
        enabled: true,
        idFactory: () {
          ids++;
          return 'trace';
        },
      );

      final context = recorder.start(stage: AiTraceStage.input);
      expect(context.enabled, isFalse);
      expect(ids, 0);
    });
  });

  test('disableAndFlush waits for queued writes and rejects later events', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (_) async {
        writes++;
        if (writes == 1) {
          started.complete();
          await release.future;
        }
      },
    );

    final context = recorder.start(stage: AiTraceStage.input);
    final flush = recorder.disableAndFlush();
    await started.future;
    expect(recorder.isEnabled, isFalse);
    var flushed = false;
    flush.then((_) => flushed = true);
    await Future<void>.value();
    expect(flushed, isFalse);

    release.complete();
    await flush;
    await recorder.record(
      context,
      stage: AiTraceStage.modelOutput,
      status: AiTraceStatus.succeeded,
    );

    expect(flushed, isTrue);
    expect(writes, 1);
  });

  test('enable resumes recording after a controlled clear', () async {
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
    );

    final first = recorder.start(stage: AiTraceStage.input);
    await recorder.disableAndFlush();
    expect(recorder.isEnabled, isFalse);
    expect(recorder.start(stage: AiTraceStage.input).enabled, isFalse);

    recorder.enable();
    expect(recorder.isEnabled, isTrue);
    final second = recorder.start(stage: AiTraceStage.input);
    await recorder.record(
      second,
      stage: AiTraceStage.modelOutput,
      status: AiTraceStatus.succeeded,
    );

    expect(first.enabled, isTrue);
    expect(events, hasLength(3));
    expect(events.map((event) => event.traceId).toSet(), hasLength(2));
  });

}
