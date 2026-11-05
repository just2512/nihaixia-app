import 'dart:convert';

import '../engine/diagnostic_engine.dart';
import '../models/diagnosis.dart';

/// Durable state for resuming a deterministic TCM interview from conversation
/// history. This stores engine input state and the outstanding prompt; it does
/// not store or synthesize a diagnosis.
class TcmInterviewTaskState {
  const TcmInterviewTaskState({
    required this.taskId,
    required this.snapshot,
    required this.status,
    this.pendingPromptId,
    this.pendingOptions = const [],
    this.updatedAt,
  });

  final String taskId;
  final EngineSnapshot snapshot;
  final String status;
  final String? pendingPromptId;
  final List<String> pendingOptions;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'taskId': taskId,
        'status': status,
        'snapshot': _snapshotToJson(snapshot),
        if (pendingPromptId != null) 'pendingPromptId': pendingPromptId,
        'pendingOptions': List<String>.unmodifiable(pendingOptions),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  factory TcmInterviewTaskState.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('TCM interview task state must be an object');
    }
    final json = Map<String, Object?>.from(decoded);
    if (json['schemaVersion'] != 1) {
      throw FormatException('Unsupported TCM task schema: ${json['schemaVersion']}');
    }
    final taskId = json['taskId'];
    final status = json['status'];
    final rawSnapshot = json['snapshot'];
    final rawOptions = json['pendingOptions'];
    final promptId = json['pendingPromptId'];
    final updatedAt = json['updatedAt'];
    if (taskId is! String ||
        taskId.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        rawSnapshot is! Map ||
        rawOptions is! List ||
        rawOptions.any((item) => item is! String) ||
        (promptId != null && promptId is! String) ||
        (updatedAt != null && updatedAt is! String)) {
      throw const FormatException('Invalid TCM interview task state');
    }
    return TcmInterviewTaskState(
      taskId: taskId,
      status: status,
      snapshot: _snapshotFromJson(Map<String, Object?>.from(rawSnapshot)),
      pendingPromptId: promptId as String?,
      pendingOptions: List<String>.unmodifiable(rawOptions.cast<String>()),
      updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt as String).toUtc(),
    );
  }

  static Map<String, Object?> _snapshotToJson(EngineSnapshot snapshot) => {
        'stage': snapshot.stage.name,
        'selectedSymptoms': snapshot.selectedSymptoms,
        'meridianDirection': snapshot.meridianDirection,
        'combinedMeridian': snapshot.combinedMeridian,
        'combinedPatternCondition': snapshot.combinedPatternCondition,
        'answers': snapshot.answers,
        'tenQuestionIndex': snapshot.tenQuestionIndex,
        'tongueCoating': snapshot.tongueCoating,
        'tongueShape': snapshot.tongueShape,
        'pulseType': snapshot.pulseType,
        'pulseTypeSecondary': snapshot.pulseTypeSecondary,
        'gender': snapshot.gender,
        'qAnswers': snapshot.qAnswers,
        'extSymptoms': snapshot.extSymptoms.toList()..sort(),
        'flatIndex': snapshot.flatIndex,
      };

  static EngineSnapshot _snapshotFromJson(Map<String, Object?> json) {
    final stageName = json['stage'];
    final stages = DiagnosticStage.values.where((stage) => stage.name == stageName);
    final selectedSymptoms = json['selectedSymptoms'];
    final answers = json['answers'];
    final qAnswers = json['qAnswers'];
    final extSymptoms = json['extSymptoms'];
    final tenQuestionIndex = json['tenQuestionIndex'];
    final flatIndex = json['flatIndex'];
    if (stages.isEmpty ||
        selectedSymptoms is! List ||
        selectedSymptoms.any((item) => item is! String) ||
        answers is! Map ||
        qAnswers is! Map ||
        qAnswers.values.any((item) => item is! int) ||
        extSymptoms is! List ||
        extSymptoms.any((item) => item is! String) ||
        tenQuestionIndex is! int ||
        flatIndex is! int) {
      throw const FormatException('Invalid TCM diagnostic engine snapshot');
    }
    String? optionalString(String key) {
      final value = json[key];
      if (value != null && value is! String) {
        throw FormatException('Invalid snapshot field: $key');
      }
      return value as String?;
    }

    return EngineSnapshot(
      stage: stages.first,
      selectedSymptoms: List<String>.unmodifiable(selectedSymptoms.cast<String>()),
      meridianDirection: optionalString('meridianDirection'),
      combinedMeridian: optionalString('combinedMeridian'),
      combinedPatternCondition: optionalString('combinedPatternCondition'),
      answers: Map<String, dynamic>.from(answers),
      tenQuestionIndex: tenQuestionIndex,
      tongueCoating: optionalString('tongueCoating'),
      tongueShape: optionalString('tongueShape'),
      pulseType: optionalString('pulseType'),
      pulseTypeSecondary: optionalString('pulseTypeSecondary'),
      gender: optionalString('gender'),
      qAnswers: Map<String, int>.from(qAnswers),
      extSymptoms: Set<String>.unmodifiable(extSymptoms.cast<String>()),
      flatIndex: flatIndex,
    );
  }
}
