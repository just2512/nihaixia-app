import '../utils/ai_model_config_validation.dart';

enum AiTaskKind {
  textReasoning('text_reasoning'),
  imageUnderstanding('image_understanding'),
  audioUnderstanding('audio_understanding'),
  embedding('embedding'),
  reranking('reranking');

  const AiTaskKind(this.key);
  final String key;

  bool get isGenerative =>
      this == textReasoning ||
      this == imageUnderstanding ||
      this == audioUnderstanding;

  static AiTaskKind fromKey(String key) => AiTaskKind.values.firstWhere(
        (value) => value.key == key,
        orElse: () => throw ArgumentError('AI_TASK_KIND_UNSUPPORTED'),
      );
}

enum AiRuntimeKind {
  local('local'),
  cloud('cloud');

  const AiRuntimeKind(this.key);
  final String key;

  static AiRuntimeKind fromKey(String key) => AiRuntimeKind.values.firstWhere(
        (value) => value.key == key,
        orElse: () => throw ArgumentError('AI_RUNTIME_KIND_UNSUPPORTED'),
      );
}

/// One task-specific model configuration. A configuration represents exactly
/// one task and one runtime; it never infers provider capabilities.
class AiModelConfig {
  AiModelConfig({
    required this.modelConfigId,
    required this.displayName,
    required this.taskKind,
    required this.runtimeKind,
    required this.modelIdentifier,
    this.providerId,
    this.localAssetId,
    this.apiProtocolId,
    this.enabled = true,
    this.modelRevision,
    this.modelFingerprint,
    this.contextWindowTokens,
    this.maxOutputTokens,
    this.tokenizerId,
    this.tokenizerRevision,
    this.maxInputTokens,
    this.embeddingDimension,
    this.embeddingNormalization,
    this.maxBatchItems,
    this.maxCandidates,
    this.maxCandidateTokens,
    this.outputProtocolId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.configSchemaVersion = 1,
  })  : createdAt = (createdAt ?? DateTime.now()).toUtc(),
        updatedAt = (updatedAt ?? DateTime.now()).toUtc() {
    requireTrimmedNonEmpty(modelConfigId, 'AI_MODEL_CONFIG_ID_INVALID');
    requireTrimmedNonEmpty(displayName, 'AI_MODEL_DISPLAY_NAME_INVALID');
    requireTrimmedNonEmpty(modelIdentifier, 'AI_MODEL_IDENTIFIER_INVALID');
    if (configSchemaVersion != 1) {
      throw ArgumentError('AI_MODEL_SCHEMA_VERSION_UNSUPPORTED');
    }

    if (runtimeKind == AiRuntimeKind.cloud) {
      if (providerId == null || providerId!.trim().isEmpty ||
          localAssetId != null ||
          apiProtocolId == null ||
          apiProtocolId!.trim().isEmpty) {
        throw ArgumentError('AI_CLOUD_MODEL_PROVIDER_OR_PROTOCOL_INVALID');
      }
    } else {
      if (localAssetId == null || localAssetId!.trim().isEmpty ||
          providerId != null ||
          apiProtocolId != null) {
        throw ArgumentError('AI_LOCAL_MODEL_ASSET_REFERENCE_INVALID');
      }
    }

    switch (taskKind) {
      case AiTaskKind.textReasoning:
      case AiTaskKind.imageUnderstanding:
      case AiTaskKind.audioUnderstanding:
        requirePositive(contextWindowTokens, 'AI_MODEL_CONTEXT_WINDOW_INVALID');
        requirePositive(maxOutputTokens, 'AI_MODEL_MAX_OUTPUT_INVALID');
        if (maxOutputTokens! >= contextWindowTokens!) {
          throw ArgumentError('AI_MODEL_OUTPUT_MUST_BE_BELOW_CONTEXT_WINDOW');
        }
        if (embeddingDimension != null ||
            embeddingNormalization != null ||
            maxBatchItems != null ||
            maxCandidates != null ||
            maxCandidateTokens != null ||
            outputProtocolId != null) {
          throw ArgumentError('AI_GENERATION_MODEL_HAS_NON_GENERATION_FIELDS');
        }
        break;
      case AiTaskKind.embedding:
        requirePositive(maxInputTokens, 'AI_EMBEDDING_INPUT_LIMIT_INVALID');
        requirePositive(embeddingDimension, 'AI_EMBEDDING_DIMENSION_INVALID');
        requirePositive(maxBatchItems, 'AI_EMBEDDING_BATCH_LIMIT_INVALID');
        if (embeddingNormalization != 'none' &&
            embeddingNormalization != 'l2') {
          throw ArgumentError('AI_EMBEDDING_NORMALIZATION_INVALID');
        }
        if (contextWindowTokens != null || maxOutputTokens != null ||
            maxCandidates != null || maxCandidateTokens != null ||
            outputProtocolId != null) {
          throw ArgumentError('AI_EMBEDDING_MODEL_HAS_UNRELATED_FIELDS');
        }
        break;
      case AiTaskKind.reranking:
        requirePositive(maxInputTokens, 'AI_RERANK_INPUT_LIMIT_INVALID');
        requirePositive(maxCandidates, 'AI_RERANK_CANDIDATE_LIMIT_INVALID');
        requirePositive(maxCandidateTokens, 'AI_RERANK_CANDIDATE_TOKEN_LIMIT_INVALID');
        requireTrimmedNonEmpty(
          outputProtocolId ?? '',
          'AI_RERANK_OUTPUT_PROTOCOL_REQUIRED',
        );
        if (contextWindowTokens != null || maxOutputTokens != null ||
            embeddingDimension != null || embeddingNormalization != null ||
            maxBatchItems != null) {
          throw ArgumentError('AI_RERANK_MODEL_HAS_UNRELATED_FIELDS');
        }
        break;
    }

    for (final value in [modelRevision, modelFingerprint, tokenizerId, tokenizerRevision]) {
      if (value != null && value.trim().isEmpty) {
        throw ArgumentError('AI_MODEL_OPTIONAL_METADATA_INVALID');
      }
    }
  }

  final String modelConfigId;
  final String displayName;
  final AiTaskKind taskKind;
  final AiRuntimeKind runtimeKind;
  final String modelIdentifier;
  final String? providerId;
  final String? localAssetId;
  final String? apiProtocolId;
  final bool enabled;
  final String? modelRevision;
  final String? modelFingerprint;
  final int? contextWindowTokens;
  final int? maxOutputTokens;
  final String? tokenizerId;
  final String? tokenizerRevision;
  final int? maxInputTokens;
  final int? embeddingDimension;
  final String? embeddingNormalization;
  final int? maxBatchItems;
  final int? maxCandidates;
  final int? maxCandidateTokens;
  final String? outputProtocolId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int configSchemaVersion;

  Map<String, Object?> toDatabaseRow() => {
        'model_config_id': modelConfigId,
        'display_name': displayName,
        'task_kind': taskKind.key,
        'runtime_kind': runtimeKind.key,
        'model_identifier': modelIdentifier,
        'provider_id': providerId,
        'local_asset_id': localAssetId,
        'api_protocol_id': apiProtocolId,
        'enabled': enabled ? 1 : 0,
        'model_revision': modelRevision,
        'model_fingerprint': modelFingerprint,
        'context_window_tokens': contextWindowTokens,
        'max_output_tokens': maxOutputTokens,
        'tokenizer_id': tokenizerId,
        'tokenizer_revision': tokenizerRevision,
        'max_input_tokens': maxInputTokens,
        'embedding_dimension': embeddingDimension,
        'embedding_normalization': embeddingNormalization,
        'max_batch_items': maxBatchItems,
        'max_candidates': maxCandidates,
        'max_candidate_tokens': maxCandidateTokens,
        'output_protocol_id': outputProtocolId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'config_schema_version': configSchemaVersion,
      };

  factory AiModelConfig.fromDatabaseRow(Map<String, Object?> row) =>
      AiModelConfig(
        modelConfigId: row['model_config_id'] as String,
        displayName: row['display_name'] as String,
        taskKind: AiTaskKind.fromKey(row['task_kind'] as String),
        runtimeKind: AiRuntimeKind.fromKey(row['runtime_kind'] as String),
        modelIdentifier: row['model_identifier'] as String,
        providerId: row['provider_id'] as String?,
        localAssetId: row['local_asset_id'] as String?,
        apiProtocolId: row['api_protocol_id'] as String?,
        enabled: row['enabled'] == 1,
        modelRevision: row['model_revision'] as String?,
        modelFingerprint: row['model_fingerprint'] as String?,
        contextWindowTokens: row['context_window_tokens'] as int?,
        maxOutputTokens: row['max_output_tokens'] as int?,
        tokenizerId: row['tokenizer_id'] as String?,
        tokenizerRevision: row['tokenizer_revision'] as String?,
        maxInputTokens: row['max_input_tokens'] as int?,
        embeddingDimension: row['embedding_dimension'] as int?,
        embeddingNormalization: row['embedding_normalization'] as String?,
        maxBatchItems: row['max_batch_items'] as int?,
        maxCandidates: row['max_candidates'] as int?,
        maxCandidateTokens: row['max_candidate_tokens'] as int?,
        outputProtocolId: row['output_protocol_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        configSchemaVersion: row['config_schema_version'] as int,
      );
}
