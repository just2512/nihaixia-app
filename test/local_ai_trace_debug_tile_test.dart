import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ai_trace.dart';
import 'package:nihaisha_app/widgets/local_ai_trace_debug_tile.dart';

void main() {
  testWidgets('TRACE is opt-in, flushes on disable, and stops recording',
      (tester) async {
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      writer: (event) async {
        events.add(event);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalAiTraceDebugTile(recorder: recorder),
        ),
      ),
    );

    expect(recorder.isEnabled, isFalse);
    expect(find.textContaining('默认关闭'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(recorder.isEnabled, isTrue);
    expect(find.textContaining('最多 500 条、保留 7 天'), findsOneWidget);

    final context = recorder.start(stage: AiTraceStage.input);
    await recorder.record(
      context,
      stage: AiTraceStage.finalRender,
      status: AiTraceStatus.succeeded,
    );
    expect(events, hasLength(2));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(recorder.isEnabled, isFalse);
    final writtenBeforeDisabledRecord = events.length;
    await recorder.record(
      context,
      stage: AiTraceStage.persistence,
      status: AiTraceStatus.succeeded,
    );
    expect(events, hasLength(writtenBeforeDisabledRecord));
  });
}
