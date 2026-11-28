import '../utils/ai_model_config_validation.dart';
import 'ai_model_config.dart';

/// Metadata for user-imported local Embedding and Reranker model assets.
/// Model bytes remain in app-private storage and are never placed in SQLite.
class AiLocalModelAsset {
  AiLocalModelAsset({
    required this.localAssetId,
    required this.modelIdentifier,
    required this.taskKind,
    required this.runtimeAdapterId,
    required this.modelFormat,
    required this.privateRelativePath,
    required this.byteLength,
    required this.sha256,
    required this.manifestJson,
    required this.installStatus,
    this.modelRevision,
    this.tokenizerId,
    this.tokenizerRevision,
    this.maxInputTokens,
    this.embeddingDimension,
    this.embeddingNormalization,
    this.maxBatchItems,
    this.maxCandidates,
    this.outputProtocolId,
    this.licenseId,
    this.licenseUrl,
    this.notice,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc() {
    requireTrimmedNonEmpty(localAssetId, 'AI_LOCAL_ASSET_ID_INVALID');
    requireTrimmedNonEmpty(modelIdentifier, 'AI_LOCAL_ASSET_MODEL_ID_INVALID');
    requireTrimmedNonEmpty(runtimeAdapterId, 'AI_LOCAL_ASSET_RUNTIME_INVALID');
    requireTrimmedNonEmpty(modelFormat, 'AI_LOCAL_ASSET_FORMAT_INVALID');
    requireTrimmedNonEmpty(manifestJson, 'AI_LOCAL_ASSET_MANIFEST_REQUIRED');
    requirePositive(byteLength, 'AI_LOCAL_ASSET_BYTE_LENGTH_INVALID');
    if (taskKind != AiTaskKind.embedding && taskKind != AiTaskKind.reranking) {
      throw ArgumentError('AI_LOCAL_ASSET_TASK_KIND_UNSUPPORTED');
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('AI_LOCAL_ASSET_SHA256_INVALID');
    }
    if (privateRelativePath.trim().isEmpty ||
        privateRelativePath != privateRelativePath.trim() ||
        privateRelativePath.startsWith('/') ||
        privateRelativePath.contains(String.fromCharCode(92)) ||
        privateRelativePath.split('/').any(
          (part) => part == '..' || part.isEmpty,
        )) {
      throw ArgumentError('AI_LOCAL_ASSET_PATH_MUST_BE_PRIVATE_RELATIVE');
    }
    if (!const {'installed', 'missing', 'invalid', 'unknown'}
        .contains(installStatus)) {
      throw ArgumentError('AI_LOCAL_ASSET_INSTALL_STATUS_INVALID');
    }
    if (taskKind == AiTaskKind.embedding) {
      requirePositive(embeddingDimension, 'AI_LOCAL_EMBEDDING_DIMENSION_INVALID');
      requirePositive(maxInputTokens, 'AI_LOCAL_EMBEDDING_INPUT_LIMIT_INVALID');
      requirePositive(maxBatchItems, 'AI_LOCAL_EMBEDDING_BATCH_LIMIT_INVALID');
      if (embeddingNormalization != 'none' &&
          embeddingNormalization != 'l2') {
        throw ArgumentError('AI_LOCAL_EMBEDDING_NORMALIZATION_INVALID');
      }
    } else {
      requirePositive(maxInputTokens, 'AI_LOCAL_RERANK_INPUT_LIMIT_INVALID');
      requirePositive(maxCandidates, 'AI_LOCAL_RERANK_CANDIDATE_LIMIT_INVALID');
      requireTrimmedNonEmpty(
        outputProtocolId ?? '',
        'AI_LOCAL_RERANK_OUTPUT_PROTOCOL_REQUIRED',
      );
    }
  }

  final String localAssetId;
  final String modelIdentifier;
  final AiTaskKind taskKind;
  final String runtimeAdapterId;
  final String modelFormat;
  final String privateRelativePath;
  final int byteLength;
  final String sha256;
  final String manifestJson;
  final String installStatus;
  final String? modelRevision;
  final String? tokenizerId;
  final String? tokenizerRevision;
  final int? maxInputTokens;
  final int? embeddingDimension;
  final String? embeddingNormalization;
  final int? maxBatchItems;
  final int? maxCandidates;
  final String? outputProtocolId;
  final String? licenseId;
  final String? licenseUrl;
  final String? notice;
  final DateTime createdAt;

  Map<String, Object?> toDatabaseRow() => {
        'local_asset_id': localAssetId,
        'model_identifier': modelIdentifier,
        'task_kind': taskKind.key,
        'runtime_adapter_id': runtimeAdapterId,
        'model_format': modelFormat,
        'private_relative_path': privateRelativePath,
        'byte_length': byteLength,
        'sha256': sha256.toLowerCase(),
        'manifest_json': manifestJson,
        'install_status': installStatus,
        'model_revision': modelRevision,
        'tokenizer_id': tokenizerId,
        'tokenizer_revision': tokenizerRevision,
        'max_input_tokens': maxInputTokens,
        'embedding_dimension': embeddingDimension,
        'embedding_normalization': embeddingNormalization,
        'max_batch_items': maxBatchItems,
        'max_candidates': maxCandidates,
        'output_protocol_id': outputProtocolId,
        'license_id': licenseId,
        'license_url': licenseUrl,
        'notice': notice,
        'created_at': createdAt.toIso8601String(),
      };

  factory AiLocalModelAsset.fromDatabaseRow(Map<String, Object?> row) =>
      AiLocalModelAsset(
        localAssetId: row['local_asset_id'] as String,
        modelIdentifier: row['model_identifier'] as String,
        taskKind: AiTaskKind.fromKey(row['task_kind'] as String),
        runtimeAdapterId: row['runtime_adapter_id'] as String,
        modelFormat: row['model_format'] as String,
        privateRelativePath: row['private_relative_path'] as String,
        byteLength: row['byte_length'] as int,
        sha256: row['sha256'] as String,
        manifestJson: row['manifest_json'] as String,
        installStatus: row['install_status'] as String,
        modelRevision: row['model_revision'] as String?,
        tokenizerId: row['tokenizer_id'] as String?,
        tokenizerRevision: row['tokenizer_revision'] as String?,
        maxInputTokens: row['max_input_tokens'] as int?,
        embeddingDimension: row['embedding_dimension'] as int?,
        embeddingNormalization: row['embedding_normalization'] as String?,
        maxBatchItems: row['max_batch_items'] as int?,
        maxCandidates: row['max_candidates'] as int?,
        outputProtocolId: row['output_protocol_id'] as String?,
        licenseId: row['license_id'] as String?,
        licenseUrl: row['license_url'] as String?,
        notice: row['notice'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
