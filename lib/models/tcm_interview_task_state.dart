import 'dart:convert';

import '../engine/diagnostic_engine.dart';
import '../models/diagnosis.dart';
import '../models/diagnosis_result_codec.dart';

/// One visible message from the structured interview transcript.
class TcmInterviewTaskMessage {
  const TcmInterviewTaskMessage({
    required this.text,
    required this.isUser,
    this.isResult = false,
  });

  final String text;
  final bool isUser;
  final bool isResult;

  Map<String, Object?> toJson() => {
        'text': text,
        'isUser': isUser,
        'isResult': isResult,
      };

  factory TcmInterviewTaskMessage.fromJson(Map<String, Object?> json) {
    final text = json['text'];
    final isUser = json['isUser'];
    final isResult = json['isResult'] ?? false;
    if (text is! String || isUser is! bool || isResult is! bool) {
      throw const FormatException('Invalid TCM interview transcript message');
    }
    return TcmInterviewTaskMessage(
      text: text,
      isUser: isUser,
      isResult: isResult,
    );
  }
}

/// Durable state for resuming a deterministic TCM interview from conversation
/// history. It stores engine input state, the visible transcript, the
/// outstanding prompt and an immutable structured result when diagnosis completes.
class TcmInterviewTaskState {
  const TcmInterviewTaskState({
    required this.taskId,
    required this.snapshot,
    required this.status,
    this.pendingPromptId,
    this.pendingPromptText,
    this.pendingOptions = const [],
    this.transcript = const [],
    this.updatedAt,
    this.completedDiagnosis,
  });

  final String taskId;
  final EngineSnapshot snapshot;
  final String status;
  final String? pendingPromptId;
  /// Exact visible wording retained across app-version changes.
  final String? pendingPromptText;
  final List<String> pendingOptions;
  final List<TcmInterviewTaskMessage> transcript;
  final DateTime? updatedAt;
  /// Immutable structured result captured at completion; never recalculated on restore.
  final DiagnosisResult? completedDiagnosis;

  Map<String, Object?> toJson() => {
        'schemaVersion': 2,
        'taskId': taskId,
        'status': status,
        'snapshot': _snapshotToJson(snapshot),
        if (pendingPromptId != null) 'pendingPromptId': pendingPromptId,
        if (pendingPromptText != null) 'pendingPromptText': pendingPromptText,
        'pendingOptions': List<String>.unmodifiable(pendingOptions),
        'transcript': transcript.map((message) => message.toJson()).toList(growable: false),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
        if (completedDiagnosis != null)
          'completedDiagnosis': DiagnosisResultCodec.toJson(completedDiagnosis!),
      };

  String encode() => jsonEncode(toJson());

  factory TcmInterviewTaskState.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('TCM interview task state must be an object');
    }
    final json = Map<String, Object?>.from(decoded);
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw FormatException('Unsupported TCM task schema: $schemaVersion');
    }
    final taskId = json['taskId'];
    final status = json['status'];
    final rawSnapshot = json['snapshot'];
    final rawOptions = json['pendingOptions'];
    final rawTranscript = json['transcript'] ?? const [];
    final promptId = json['pendingPromptId'];
    final promptText = json['pendingPromptText'];
    final updatedAt = json['updatedAt'];
    final rawCompletedDiagnosis = json['completedDiagnosis'];
    if (taskId is! String ||
        taskId.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        rawSnapshot is! Map ||
        rawOptions is! List ||
        rawOptions.any((item) => item is! String) ||
        rawTranscript is! List ||
        rawTranscript.any((item) => item is! Map) ||
        (promptId != null && promptId is! String) ||
        (promptText != null && promptText is! String) ||
        (updatedAt != null && updatedAt is! String) ||
        (rawCompletedDiagnosis != null && rawCompletedDiagnosis is! Map) ||
        (rawCompletedDiagnosis != null && status != 'completed')) {
      throw const FormatException('Invalid TCM interview task state');
    }
    return TcmInterviewTaskState(
      taskId: taskId,
      status: status,
      snapshot: _snapshotFromJson(Map<String, Object?>.from(rawSnapshot)),
      pendingPromptId: promptId as String?,
      pendingPromptText: promptText as String?,
      pendingOptions: List<String>.unmodifiable(rawOptions.cast<String>()),
      transcript: List<TcmInterviewTaskMessage>.unmodifiable(
        rawTranscript.map((item) => TcmInterviewTaskMessage.fromJson(
          Map<String, Object?>.from(item as Map),
        )),
      ),
      updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt as String).toUtc(),
      completedDiagnosis: rawCompletedDiagnosis == null
          ? null
          : DiagnosisResultCodec.fromJson(
              Map<String, dynamic>.from(rawCompletedDiagnosis as Map),
            ),
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
