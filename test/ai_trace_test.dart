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
      const event = AiTraceEvent(
        traceId: 'trace',
        stage: AiTraceStage.retrieval,
        status: AiTraceStatus.succeeded,
        occurredAt: DateTime.utc(2026, 11, 11),
        sourceIds: ['formula:guizhi_tang'],
      );

      final json = event.toJson();
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
}
