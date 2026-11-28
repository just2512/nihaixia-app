import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ai_trace.dart';
import 'package:nihaisha_app/services/ai_trace_store.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-trace-store-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  AiTraceEvent event(String id, DateTime time) => AiTraceEvent(
        traceId: id,
        stage: AiTraceStage.input,
        status: AiTraceStatus.notStarted,
        occurredAt: time,
        route: 'consultation',
      );

  test('writes only allowlisted metadata to the app-private trace file',
      () async {
    final writer = LocalAiTraceFileWriter(
      directoryProvider: () async => directory,
      clock: () => DateTime.utc(2026, 11, 11, 12),
    );

    await writer(event('trace-1', DateTime.utc(2026, 11, 11, 11)));

    final file = File('${directory.path}/ai_trace.jsonl');
    final row = jsonDecode((await file.readAsLines()).single) as Map;
    expect(row['trace_id'], 'trace-1');
    expect(row['status'], 'NOT_STARTED');
    expect(row.keys, isNot(contains('prompt')));
    expect(row.keys, isNot(contains('response')));
    expect(row.keys, isNot(contains('symptoms')));
    expect(row.keys, isNot(contains('attachment_path')));
  });

  test('drops expired records and keeps at most maxEvents', () async {
    final writer = LocalAiTraceFileWriter(
      directoryProvider: () async => directory,
      clock: () => DateTime.utc(2026, 11, 11, 12),
      maxEvents: 2,
      retention: const Duration(days: 7),
    );

    await writer(event('expired', DateTime.utc(2026, 11, 1)));
    await writer(event('recent-1', DateTime.utc(2026, 11, 10)));
    await writer(event('recent-2', DateTime.utc(2026, 11, 11)));
    await writer(event('recent-3', DateTime.utc(2026, 11, 11, 11)));

    final file = File('${directory.path}/ai_trace.jsonl');
    final rows = (await file.readAsLines())
        .map((line) => jsonDecode(line) as Map)
        .toList();

    expect(rows, hasLength(2));
    expect(rows.map((row) => row['trace_id']).toList(),
        ['recent-2', 'recent-3']);
  });

  test('serializes concurrent writes without losing event order', () async {
    final writer = LocalAiTraceFileWriter(
      directoryProvider: () async => directory,
      clock: () => DateTime.utc(2026, 11, 11, 12),
      maxEvents: 10,
    );

    await Future.wait([
      writer(event('one', DateTime.utc(2026, 11, 11, 10))),
      writer(event('two', DateTime.utc(2026, 11, 11, 10, 1))),
      writer(event('three', DateTime.utc(2026, 11, 11, 10, 2))),
    ]);

    final file = File('${directory.path}/ai_trace.jsonl');
    final rows = (await file.readAsLines())
        .map((line) => jsonDecode(line) as Map)
        .toList();
    expect(rows.map((row) => row['trace_id']).toList(), ['one', 'two', 'three']);
  });

  test('clear deletes only the trace file and its temp file', () async {
    final writer = LocalAiTraceFileWriter(
      directoryProvider: () async => directory,
    );
    final unrelated = File('${directory.path}/unrelated.txt');
    await unrelated.writeAsString('keep');
    await writer(event('trace', DateTime.utc(2026, 11, 11)));
    await File('${directory.path}/ai_trace.jsonl.tmp').writeAsString('partial');

    await writer.clear();

    expect(await File('${directory.path}/ai_trace.jsonl').exists(), isFalse);
    expect(await File('${directory.path}/ai_trace.jsonl.tmp').exists(), isFalse);
    expect(await unrelated.readAsString(), 'keep');
  });
}
