import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/screens/chat_screen.dart';

void main() {
  testWidgets('restores the saved prompt and persists the next prompt after an answer',
      (tester) async {
    final engine = DiagnosticEngine();
    final temperatureOptions = engine.getTemperatureQuestions();
    final savedStates = <TcmInterviewTaskState>[];
    const savedPrompt = '恢复时必须保留的原始寒热题面';

    final task = TcmInterviewTaskState(
      taskId: 'resume-test-1',
      status: 'in_progress',
      snapshot: engine.createSnapshot(),
      pendingPromptId: 'temperature',
      pendingPromptText: savedPrompt,
      pendingOptions: temperatureOptions.map((option) => option.label).toList(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          initialTaskState: task,
          onTaskStateChanged: (state) async {
            savedStates.add(state);
          },
        ),
      ),
    );

    expect(find.text(savedPrompt), findsOneWidget);
    expect(find.text(temperatureOptions.first.label), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(temperatureOptions.first.label).last);
    await tester.pumpAndSettle();

    expect(
      find.text('接下来请告诉我你的舌象和脉象（可跳过）：'),
      findsOneWidget,
    );
    expect(savedStates, isNotEmpty);
    expect(savedStates.last.status, 'in_progress');
    expect(savedStates.last.pendingPromptId, 'tongue_pulse');
    expect(
      savedStates.last.snapshot.answers['temperature'],
      temperatureOptions.first.key,
    );
    expect(tester.takeException(), isNull);
  });
}
