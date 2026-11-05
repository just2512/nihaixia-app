import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/services/tcm_interview_adapter.dart';

void main() {
  group('TcmInterviewTaskState', () {
    test('persists and restores a pending interview including canonical pulse data', () {
      final adapter = TcmInterviewAdapter();
      adapter.answerTemperature('fever_chills');
      adapter.answerTonguePulse(
        tongueCoating: '薄白',
        tongueShape: '淡白',
        primaryPulse: '弦',
        secondaryPulse: '滑',
      );
      final state = TcmInterviewTaskState(
        taskId: 'consult-42',
        snapshot: adapter.createSnapshot(),
        status: 'awaiting_follow_up',
        pendingPromptId: 'pulse_cross_drink',
        pendingOptions: const ['不渴', '口渴，喜热饮'],
        updatedAt: DateTime.utc(2026, 11, 5),
      );

      final restoredState = TcmInterviewTaskState.decode(state.encode());
      final restored = TcmInterviewAdapter(snapshot: restoredState.snapshot);
      expect(restoredState.taskId, 'consult-42');
      expect(restoredState.status, 'awaiting_follow_up');
      expect(restoredState.pendingPromptId, 'pulse_cross_drink');
      expect(restoredState.pendingOptions, state.pendingOptions);
      expect(restored.stage, DiagnosticStage.tenQuestions);
      expect(restored.createSnapshot().pulseType, '弦');
      expect(restored.createSnapshot().pulseTypeSecondary, '滑');
      expect(restored.createSnapshot().answers['temperature'], 'fever_chills');
    });

    test('preserves unanswered and unknown state without fabricating a diagnosis', () {
      final adapter = TcmInterviewAdapter();
      final state = TcmInterviewTaskState(
        taskId: 'consult-43',
        snapshot: adapter.createSnapshot(),
        status: 'in_progress',
      );
      final restored = TcmInterviewTaskState.decode(state.encode());
      expect(restored.status, 'in_progress');
      expect(restored.snapshot.stage, DiagnosticStage.temperaturePattern);
      expect(restored.snapshot.answers, isEmpty);
    });

    test('rejects unsupported schema and malformed snapshot fields', () {
      expect(
        () => TcmInterviewTaskState.decode('{"schemaVersion":9}'),
        throwsFormatException,
      );
      expect(
        () => TcmInterviewTaskState.decode(
          '{"schemaVersion":1,"taskId":"x","status":"active",'
          '"snapshot":{"stage":"not_a_stage"},"pendingOptions":[]}',
        ),
        throwsFormatException,
      );
    });
  });
}
