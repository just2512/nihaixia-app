import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/engine/formula_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/models/diagnosis_result_codec.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';

void main() {
  group('TcmInterviewTaskState', () {
    test('round-trips the complete diagnostic snapshot and pending prompt', () {
      final original = TcmInterviewTaskState(
        taskId: 'interview-2026-11-05-001',
        status: 'in_progress',
        pendingPromptId: 'combined_clause172_diarrhea',
        pendingPromptText: '第172条所述自下利情况是否存在？',
        pendingOptions: const ['明确有自下利', '明确没有下利', '不确定'],
        transcript: const [
          TcmInterviewTaskMessage(text: '你目前有什么不适？', isUser: false),
          TcmInterviewTaskMessage(text: '恶心、口苦', isUser: true),
          TcmInterviewTaskMessage(text: '已记录舌脉信息', isUser: false),
        ],
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
      expect(restored.pendingPromptText, original.pendingPromptText);
      expect(restored.pendingOptions, original.pendingOptions);
      expect(restored.transcript.map((message) => message.text).toList(), [
        '你目前有什么不适？',
        '恶心、口苦',
        '已记录舌脉信息',
      ]);
      expect(restored.transcript.map((message) => message.isUser).toList(), [
        false,
        true,
        false,
      ]);
      expect(restored.updatedAt, original.updatedAt);
      expect(restored.snapshot.stage, DiagnosticStage.meridianLocation);
      expect(restored.snapshot.selectedSymptoms, ['恶心', '口苦']);
      expect(restored.snapshot.meridianDirection, '少阳');
      expect(restored.snapshot.combinedMeridian, '太阳少阳');
      expect(
        restored.snapshot.combinedPatternCondition,
        CombinedPatternCondition.sunShaoyangVomit,
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


    test('canonicalizes historical combined condition keys on task-state read and write', () {
      final state = TcmInterviewTaskState(
        taskId: 'legacy-combined-key',
        status: 'in_progress',
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          answers: const {},
          tenQuestionIndex: 0,
          combinedPatternCondition: 'sun+shaoyang_vomit',
        ),
      );

      final encoded = state.toJson();
      final encodedSnapshot =
          Map<String, Object?>.from(encoded['snapshot']! as Map);
      expect(
        encodedSnapshot['combinedPatternCondition'],
        CombinedPatternCondition.sunShaoyangVomit,
      );

      // Simulate a pre-canonical SQLite row written by an older app version.
      encodedSnapshot['combinedPatternCondition'] = 'sun+shaoyang_vomit';
      encoded['snapshot'] = encodedSnapshot;
      final restored = TcmInterviewTaskState.decode(jsonEncode(encoded));
      expect(
        restored.snapshot.combinedPatternCondition,
        CombinedPatternCondition.sunShaoyangVomit,
      );

      final rewritten = jsonDecode(restored.encode()) as Map<String, dynamic>;
      final rewrittenSnapshot = rewritten['snapshot'] as Map<String, dynamic>;
      expect(
        rewrittenSnapshot['combinedPatternCondition'],
        CombinedPatternCondition.sunShaoyangVomit,
      );
    });

    test('round-trips the completed structured diagnosis without recalculation', () {
      final diagnosis = DiagnosisResult(
        meridian: '少阳',
        pattern: '少阳证',
        patternDetail: '往来寒热，胸胁苦满。',
        formula: '小柴胡汤',
        recommendedFormulas: const ['小柴胡汤', '柴胡桂枝汤'],
        explanation: '规则引擎结果快照',
        confidence: 0.75,
        matchedSymptoms: const ['口苦', '往来寒热'],
        followUpQuestions: const ['是否口苦？'],
        combinedMeridian: '太阳',
        tongueCoating: '薄白',
        tongueShape: '淡红',
        pulseType: '弦',
        pulseTypeSecondary: '数',
        careAdvice: const {'饮食': ['清淡饮食'], '起居': ['规律作息']},
        differential: DifferentialDiagnosisResult(
          name1: '少阳证',
          formula1: '小柴胡汤',
          name2: '太阳少阳合病',
          formula2: '柴胡桂枝汤',
          keyDifference: '表证是否仍在',
          details: const {'表证': '待核'},
        ),
        prescription: const FormulaPrescription(
          formulaName: '小柴胡汤',
          components: [
            PrescriptionComponent(name: '柴胡', dosage: '24g', role: '君药'),
            PrescriptionComponent(name: '黄芩', dosage: '9g', role: '臣药'),
          ],
          dosage: '水煎服',
          preparation: '先煮柴胡',
          contraindication: '需医师辨证核实',
          modifications: [
            FormulaModification(
              condition: '胸胁苦满',
              symptom: '胸胁满',
              type: ModificationType.add,
              herbName: '枳壳',
              resultFormula: '加减方',
              description: '结构化加减记录',
            ),
          ],
        ),
        answers: const {'bitter_mouth': true, 'temperature': 'alternating'},
        trueFalseHeatCold: const TrueFalseHeatCold(
          type: '真寒假热',
          description: '真假寒热鉴别快照',
          dimensions: {'口渴': '不渴'},
        ),
        medicationRules: const [
          MedicationRule(
            category: '禁忌',
            condition: '适用条件',
            prohibition: '禁忌内容',
            reason: '原因',
            emergencyTreatment: '误治急救',
          ),
        ],
        sweatingContraindications: const [
          SweatingContraindication(
            condition: '禁汗条件',
            reason: '原因',
            consequence: '后果',
          ),
        ],
        bloodStasisSigns: const [
          BloodStasisSign(
            method: '望诊',
            description: '舌绛紫',
            clinicalSignificance: '提示线索',
          ),
        ],
        pulseCombination: const PulseCombination(
          pulse1: '弦',
          pulse2: '数',
          meridian: '少阳',
          formula: '小柴胡汤',
          description: '组合脉象',
        ),
        facialComplexion: const FacialComplexion(
          color: '面红',
          meridian: '少阳',
          formula: '小柴胡汤',
          description: '面色记录',
        ),
        patternDifferential: const PatternDifferential(
          pattern1: '少阳证',
          pattern2: '太阳证',
          classicText: '原文片段',
          keyPoint: '鉴别点',
          niNote: '讲解注记',
        ),
        transmission: const MeridianTransmission(
          from: '太阳',
          to: '少阳',
          sign: '传经线索',
          treatment: '和解少阳',
        ),
        transmissionWarning: '传经预警',
        pulseTongueContradiction: '脉舌信息不一致',
        pulseTongueAssessment: const PulseTongueAssessment(
          status: 'REVIEW_REQUIRED',
          supportingEvidence: ['口苦'],
          contradictingEvidence: ['脉象待核'],
          missingEvidence: ['原始脉诊记录'],
          followUpQuestionKeys: ['pulse_cross_shaoyang'],
          followUpQuestions: ['是否有少阳相关线索？'],
        ),
        recommendConsult: true,
      );
      final state = TcmInterviewTaskState(
        taskId: 'completed-task',
        status: 'completed',
        snapshot: DiagnosticEngine().createSnapshot(),
        transcript: const [
          TcmInterviewTaskMessage(text: '辨证结果', isUser: false, isResult: true),
        ],
        completedDiagnosis: diagnosis,
      );

      final restored = TcmInterviewTaskState.decode(state.encode());
      expect(restored.status, 'completed');
      expect(restored.completedDiagnosis, isNotNull);
      expect(
        DiagnosisResultCodec.toJson(restored.completedDiagnosis!),
        DiagnosisResultCodec.toJson(diagnosis),
      );
      expect(restored.completedDiagnosis!.prescription!.components.first.dosage, '24g');
      expect(restored.completedDiagnosis!.pulseTongueAssessment!.missingEvidence,
          ['原始脉诊记录']);
    });

    test('old schema-1 records without transcript remain readable', () {
      final legacyJson = TcmInterviewTaskState(
        taskId: 'legacy-task',
        status: 'in_progress',
        snapshot: EngineSnapshot(
          stage: DiagnosticStage.temperaturePattern,
          selectedSymptoms: const [],
          answers: const {},
          tenQuestionIndex: 0,
          qAnswers: const {},
          extSymptoms: const {},
          flatIndex: 0,
        ),
      ).toJson()
        ..['schemaVersion'] = 1
        ..remove('transcript');
      final legacy = TcmInterviewTaskState.decode(jsonEncode(legacyJson));
      expect(legacy.transcript, isEmpty);
    });

    test('rejects unsupported schema versions instead of silently restoring', () {
      expect(
        () => TcmInterviewTaskState.decode(
          '{"schemaVersion":3,"taskId":"task-1","status":"in_progress",'
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
          '"pendingPromptText":42,"snapshot":{},"pendingOptions":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => TcmInterviewTaskState.decode(
          '{"schemaVersion":1,"taskId":"task-1","status":"in_progress",'
          '"transcript":[{"text":"bad","isUser":"yes"}],'
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
