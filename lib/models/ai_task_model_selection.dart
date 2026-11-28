import 'ai_model_config.dart';

enum AiTaskModelSelectionMode {
  explicit('explicit'),
  inheritTextReasoning('inherit_text_reasoning'),
  deterministicUnconfigured('deterministic_unconfigured');

  const AiTaskModelSelectionMode(this.key);
  final String key;

  static AiTaskModelSelectionMode fromKey(String key) =>
      AiTaskModelSelectionMode.values.firstWhere(
        (value) => value.key == key,
        orElse: () => throw ArgumentError('AI_SELECTION_MODE_UNSUPPORTED'),
      );
}

/// Exactly one persisted selection slot per task. Embedding and Reranking
/// never inherit from text_reasoning.
class AiTaskModelSelection {
  AiTaskModelSelection({
    required this.taskKind,
    required this.selectionMode,
    this.modelConfigId,
    DateTime? updatedAt,
  }) : updatedAt = (updatedAt ?? DateTime.now()).toUtc() {
    switch (selectionMode) {
      case AiTaskModelSelectionMode.explicit:
        if (modelConfigId == null || modelConfigId!.trim().isEmpty ||
            modelConfigId != modelConfigId!.trim()) {
          throw ArgumentError('AI_EXPLICIT_SELECTION_REQUIRES_MODEL');
        }
        break;
      case AiTaskModelSelectionMode.inheritTextReasoning:
        if (taskKind != AiTaskKind.imageUnderstanding &&
            taskKind != AiTaskKind.audioUnderstanding) {
          throw ArgumentError('AI_TASK_CANNOT_INHERIT_TEXT_REASONING');
        }
        if (modelConfigId != null) {
          throw ArgumentError('AI_INHERITED_SELECTION_CANNOT_SET_MODEL');
        }
        break;
      case AiTaskModelSelectionMode.deterministicUnconfigured:
        if (taskKind != AiTaskKind.embedding &&
            taskKind != AiTaskKind.reranking) {
          throw ArgumentError('AI_TASK_CANNOT_USE_DETERMINISTIC_UNCONFIGURED');
        }
        if (modelConfigId != null) {
          throw ArgumentError('AI_DETERMINISTIC_SELECTION_CANNOT_SET_MODEL');
        }
        break;
    }
    if (taskKind == AiTaskKind.textReasoning &&
        selectionMode != AiTaskModelSelectionMode.explicit) {
      throw ArgumentError('AI_TEXT_REASONING_REQUIRES_EXPLICIT_MODEL');
    }
    if ((taskKind == AiTaskKind.embedding || taskKind == AiTaskKind.reranking) &&
        selectionMode == AiTaskModelSelectionMode.inheritTextReasoning) {
      throw ArgumentError('AI_RETRIEVAL_TASK_CANNOT_INHERIT_CHAT_MODEL');
    }
  }

  final AiTaskKind taskKind;
  final AiTaskModelSelectionMode selectionMode;
  final String? modelConfigId;
  final DateTime updatedAt;

  Map<String, Object?> toDatabaseRow() => {
        'task_key': taskKind.key,
        'model_config_id': modelConfigId,
        'selection_mode': selectionMode.key,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory AiTaskModelSelection.fromDatabaseRow(Map<String, Object?> row) =>
      AiTaskModelSelection(
        taskKind: AiTaskKind.fromKey(row['task_key'] as String),
        selectionMode:
            AiTaskModelSelectionMode.fromKey(row['selection_mode'] as String),
        modelConfigId: row['model_config_id'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
