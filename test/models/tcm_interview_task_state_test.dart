import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';

void main() {
  group('TcmInterviewTaskState', () {
    test('round-trips the complete diagnostic snapshot and pending prompt', () {
      final original = TcmInterviewTaskState(
        taskId: 'interview-2026-11-05-001',
        status: 'in_progress',
        pendingPromptId: 'combined_clause172_diarrhea',
        pendingOptions: const ['明确有自下利', '明确没有下利', '不确定'],
        updatedAt: DateTime.utc(2026, 11, 5, 12, 30),
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const ['恶心', '口苦'],
          meridianDirection: '少阳',
          combinedMeridian: '太阳少阳',
          combinedPatternCondition: 'combined.sun_shaoyang.vomit',
          answers: const {
            'nausea': true,
            'bitter_mouth': true,
            'diarrhea': null,
            'temperature': 'fever_chills',
          },
          tenQuestionIndex: 7,
          tongueCoating: '黄腻',
          tongueShape: '齿痕',
          pulseType: '滑',
          pulseTypeSecondary: '数',
          gender: '女',
          qAnswers: const {kQ1: 1, kQ4: 2},
          extSymptoms: const {'夜间口渴', '心烦'},
          flatIndex: 3,
        ),
      );

      final restored = TcmInterviewTaskState.decode(original.encode());

      expect(restored.taskId, original.taskId);
      expect(restored.status, 'in_progress');
      expect(restored.pendingPromptId, original.pendingPromptId);
      expect(restored.pendingOptions, original.pendingOptions);
      expect(restored.updatedAt, original.updatedAt);
      expect(restored.snapshot.stage, DiagnosticStage.meridianLocation);
      expect(restored.snapshot.selectedSymptoms, ['恶心', '口苦']);
      expect(restored.snapshot.meridianDirection, '少阳');
      expect(restored.snapshot.combinedMeridian, '太阳少阳');
      expect(
        restored.snapshot.combinedPatternCondition,
        'combined.sun_shaoyang.vomit',
      );
      expect(restored.snapshot.answers, original.snapshot.answers);
      expect(restored.snapshot.tenQuestionIndex, 7);
      expect(restored.snapshot.tongueCoating, '黄腻');
      expect(restored.snapshot.tongueShape, '齿痕');
      expect(restored.snapshot.pulseType, '滑');
      expect(restored.snapshot.pulseTypeSecondary, '数');
      expect(restored.snapshot.gender, '女');
      expect(restored.snapshot.qAnswers, original.snapshot.qAnswers);
      expect(restored.snapshot.extSymptoms, {'夜间口渴', '心烦'});
      expect(restored.snapshot.flatIndex, 3);
    });

    test('rejects unsupported schema versions instead of silently restoring', () {
      expect(
        () => TcmInterviewTaskState.decode(
          '{"schemaVersion":2,"taskId":"task-1","status":"in_progress",'
          '"snapshot":{},"pendingOptions":[]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed task metadata and malformed snapshot fields', () {
      expect(
        () => TcmInterviewTaskState.decode(
          '{"schemaVersion":1,"taskId":" ","status":"in_progress",'
          '"snapshot":{},"pendingOptions":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => TcmInterviewTaskState.decode(
          '{"schemaVersion":1,"taskId":"task-1","status":"in_progress",'
          '"snapshot":{"stage":"not_a_stage","selectedSymptoms":[],"answers":{},'
          '"qAnswers":{},"extSymptoms":[],"tenQuestionIndex":0,"flatIndex":0},'
          '"pendingOptions":[]}',
        ),
        throwsFormatException,
      );
    });
  });
}
