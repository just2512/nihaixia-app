import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import '../models/ai_local_model_asset.dart';
import '../models/ai_model_config.dart';
import '../models/ai_provider_config.dart';
import '../models/ai_task_model_selection.dart';

/// Structured persistence for Provider, Model, Local Asset and task-selection
/// metadata. API secrets are deliberately outside this repository and belong
/// in AiCredentialVault; only opaque credentialRef values may be persisted.
class AiModelConfigRepository {
  AiModelConfigRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _databaseHelper;

  Future<List<AiProviderConfig>> listProviders() async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_provider_configs',
      orderBy: 'display_name COLLATE NOCASE, provider_id',
    );
    return rows.map(AiProviderConfig.fromDatabaseRow).toList(growable: false);
  }

  Future<AiProviderConfig?> getProvider(String providerId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_provider_configs',
      where: 'provider_id = ?',
      whereArgs: [providerId],
      limit: 1,
    );
    return rows.isEmpty ? null : AiProviderConfig.fromDatabaseRow(rows.single);
  }

  Future<void> saveProvider(AiProviderConfig provider) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'ai_provider_configs',
        columns: ['created_at'],
        where: 'provider_id = ?',
        whereArgs: [provider.providerId],
        limit: 1,
      );
      final row = provider.toDatabaseRow();
      row['created_at'] = existing.isEmpty
          ? provider.createdAt.toIso8601String()
          : existing.single['created_at'];
      row['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await txn.insert(
        'ai_provider_configs',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteProvider(String providerId) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final usedByModels = await txn.query(
        'ai_model_configs',
        columns: ['model_config_id'],
        where: 'provider_id = ?',
        whereArgs: [providerId],
        limit: 1,
      );
      if (usedByModels.isNotEmpty) {
        throw StateError('AI_PROVIDER_IN_USE_BY_MODELS');
      }
      await txn.delete(
        'ai_provider_configs',
        where: 'provider_id = ?',
        whereArgs: [providerId],
      );
    });
  }

  Future<List<AiLocalModelAsset>> listLocalAssets({
    AiTaskKind? taskKind,
  }) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_local_model_assets',
      where: taskKind == null ? null : 'task_kind = ?',
      whereArgs: taskKind == null ? null : [taskKind.key],
      orderBy: 'created_at DESC, local_asset_id',
    );
    return rows
        .map(AiLocalModelAsset.fromDatabaseRow)
        .toList(growable: false);
  }

  Future<AiLocalModelAsset?> getLocalAsset(String localAssetId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_local_model_assets',
      where: 'local_asset_id = ?',
      whereArgs: [localAssetId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : AiLocalModelAsset.fromDatabaseRow(rows.single);
  }

  Future<void> saveLocalAsset(AiLocalModelAsset asset) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'ai_local_model_assets',
        where: 'local_asset_id = ?',
        whereArgs: [asset.localAssetId],
        limit: 1,
      );
      final row = asset.toDatabaseRow();
      if (existing.isNotEmpty) {
        final previous = existing.single;
        final usedByModels = await txn.query(
          'ai_model_configs',
          columns: ['model_config_id'],
          where: 'local_asset_id = ?',
          whereArgs: [asset.localAssetId],
          limit: 1,
        );
        if (usedByModels.isNotEmpty) {
          // An asset ID identifies one immutable model/embedding space. Only
          // install status may change while ModelConfigs reference this row.
          // A new SHA, manifest, tokenizer, dimension or model must get a new
          // localAssetId so later IndexGenerations cannot inherit stale IDs.
          const immutableFields = [
            'model_identifier',
            'task_kind',
            'asset_source',
            'runtime_adapter_id',
            'model_format',
            'private_relative_path',
            'byte_length',
            'sha256',
            'manifest_json',
            'model_revision',
            'tokenizer_id',
            'tokenizer_revision',
            'max_input_tokens',
            'context_window_tokens',
            'max_output_tokens',
            'embedding_dimension',
            'embedding_normalization',
            'max_batch_items',
            'max_candidates',
            'output_protocol_id',
            'license_id',
            'license_url',
            'notice',
          ];
          for (final field in immutableFields) {
            if (previous[field] != row[field]) {
              throw StateError('AI_LOCAL_ASSET_IDENTITY_IN_USE_CREATE_NEW_ASSET');
            }
          }
        }
        row['created_at'] = previous['created_at'];
      } else {
        row['created_at'] = asset.createdAt.toIso8601String();
      }
      await txn.insert(
        'ai_local_model_assets',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteLocalAsset(String localAssetId) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final usedByModels = await txn.query(
        'ai_model_configs',
        columns: ['model_config_id'],
        where: 'local_asset_id = ?',
        whereArgs: [localAssetId],
        limit: 1,
      );
      if (usedByModels.isNotEmpty) {
        throw StateError('AI_LOCAL_ASSET_IN_USE_BY_MODELS');
      }
      await txn.delete(
        'ai_local_model_assets',
        where: 'local_asset_id = ?',
        whereArgs: [localAssetId],
      );
    });
  }

  Future<List<AiModelConfig>> listModelConfigs({
    AiTaskKind? taskKind,
    AiRuntimeKind? runtimeKind,
    bool includeDisabled = true,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (taskKind != null) {
      clauses.add('task_kind = ?');
      args.add(taskKind.key);
    }
    if (runtimeKind != null) {
      clauses.add('runtime_kind = ?');
      args.add(runtimeKind.key);
    }
    if (!includeDisabled) clauses.add('enabled = 1');

    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_model_configs',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'display_name COLLATE NOCASE, model_config_id',
    );
    return rows.map(AiModelConfig.fromDatabaseRow).toList(growable: false);
  }

  Future<AiModelConfig?> getModelConfig(String modelConfigId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_model_configs',
      where: 'model_config_id = ?',
      whereArgs: [modelConfigId],
      limit: 1,
    );
    return rows.isEmpty ? null : AiModelConfig.fromDatabaseRow(rows.single);
  }

  Future<void> saveModelConfig(AiModelConfig config) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      if (config.runtimeKind == AiRuntimeKind.cloud) {
        final providers = await txn.query(
          'ai_provider_configs',
          columns: ['enabled'],
          where: 'provider_id = ?',
          whereArgs: [config.providerId],
          limit: 1,
        );
        if (providers.isEmpty) {
          throw StateError('AI_MODEL_PROVIDER_NOT_FOUND');
        }
        if (config.enabled && providers.single['enabled'] != 1) {
          throw StateError('AI_MODEL_PROVIDER_DISABLED');
        }
      } else {
        final assets = await txn.query(
          'ai_local_model_assets',
          where: 'local_asset_id = ?',
          whereArgs: [config.localAssetId],
          limit: 1,
        );
        if (assets.isEmpty) {
          throw StateError('AI_MODEL_LOCAL_ASSET_NOT_FOUND');
        }
        final asset = assets.single;
        if (asset['task_kind'] != config.taskKind.key) {
          throw StateError('AI_MODEL_LOCAL_ASSET_TASK_KIND_MISMATCH');
        }
        if (asset['model_identifier'] != config.modelIdentifier) {
          throw StateError('AI_MODEL_LOCAL_ASSET_MODEL_IDENTIFIER_MISMATCH');
        }
        final assetSha = (asset['sha256'] as String).toLowerCase();
        if (config.modelFingerprint == null ||
            config.modelFingerprint!.toLowerCase() != assetSha) {
          throw StateError('AI_MODEL_LOCAL_ASSET_FINGERPRINT_REQUIRED_OR_MISMATCH');
        }
        if (asset['model_revision'] != config.modelRevision ||
            asset['tokenizer_id'] != config.tokenizerId ||
            asset['tokenizer_revision'] != config.tokenizerRevision) {
          throw StateError('AI_MODEL_LOCAL_ASSET_REVISION_OR_TOKENIZER_MISMATCH');
        }

        switch (config.taskKind) {
          case AiTaskKind.embedding:
            if (asset['max_input_tokens'] != config.maxInputTokens ||
                asset['embedding_dimension'] != config.embeddingDimension ||
                asset['embedding_normalization'] !=
                    config.embeddingNormalization ||
                asset['max_batch_items'] != config.maxBatchItems) {
              throw StateError('AI_LOCAL_EMBEDDING_ASSET_METADATA_MISMATCH');
            }
            break;
          case AiTaskKind.reranking:
            if (asset['max_input_tokens'] != config.maxInputTokens ||
                asset['max_candidates'] != config.maxCandidates ||
                asset['output_protocol_id'] != config.outputProtocolId) {
              throw StateError('AI_LOCAL_RERANKING_ASSET_METADATA_MISMATCH');
            }
            break;
          case AiTaskKind.textReasoning:
          case AiTaskKind.imageUnderstanding:
          case AiTaskKind.audioUnderstanding:
            if (asset['context_window_tokens'] != config.contextWindowTokens ||
                asset['max_output_tokens'] != config.maxOutputTokens) {
              throw StateError('AI_LOCAL_GENERATION_ASSET_METADATA_MISMATCH');
            }
            break;
        }
      }

      final existing = await txn.query(
        'ai_model_configs',
        columns: ['created_at', 'task_kind'],
        where: 'model_config_id = ?',
        whereArgs: [config.modelConfigId],
        limit: 1,
      );
      final selected = await txn.query(
        'ai_task_model_selections',
        columns: ['task_key'],
        where: 'model_config_id = ?',
        whereArgs: [config.modelConfigId],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          existing.single['task_kind'] != config.taskKind.key &&
          selected.isNotEmpty) {
        throw StateError('AI_MODEL_TASK_KIND_IN_USE_BY_SELECTION');
      }
      if (!config.enabled && selected.isNotEmpty) {
        throw StateError('AI_MODEL_CONFIG_IN_USE_BY_TASK_SELECTION');
      }

      final row = config.toDatabaseRow();
      row['created_at'] = existing.isEmpty
          ? config.createdAt.toIso8601String()
          : existing.single['created_at'];
      row['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await txn.insert(
        'ai_model_configs',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteModelConfig(String modelConfigId) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final selected = await txn.query(
        'ai_task_model_selections',
        columns: ['task_key'],
        where: 'model_config_id = ?',
        whereArgs: [modelConfigId],
        limit: 1,
      );
      if (selected.isNotEmpty) {
        throw StateError('AI_MODEL_CONFIG_IN_USE_BY_TASK_SELECTION');
      }
      await txn.delete(
        'ai_model_configs',
        where: 'model_config_id = ?',
        whereArgs: [modelConfigId],
      );
    });
  }

  Future<List<AiTaskModelSelection>> listTaskSelections() async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_task_model_selections',
      orderBy: 'task_key',
    );
    return rows
        .map(AiTaskModelSelection.fromDatabaseRow)
        .toList(growable: false);
  }

  Future<AiTaskModelSelection?> getTaskSelection(AiTaskKind taskKind) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'ai_task_model_selections',
      where: 'task_key = ?',
      whereArgs: [taskKind.key],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : AiTaskModelSelection.fromDatabaseRow(rows.single);
  }

  Future<void> saveTaskSelection(AiTaskModelSelection selection) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      if (selection.selectionMode ==
          AiTaskModelSelectionMode.inheritTextReasoning) {
        final defaultSelection = await txn.query(
          'ai_task_model_selections',
          where: 'task_key = ?',
          whereArgs: [AiTaskKind.textReasoning.key],
          limit: 1,
        );
        if (defaultSelection.isEmpty ||
            defaultSelection.single['selection_mode'] !=
                AiTaskModelSelectionMode.explicit.key) {
          throw StateError('AI_TEXT_REASONING_SELECTION_REQUIRED_FOR_INHERITANCE');
        }
      }

      if (selection.selectionMode == AiTaskModelSelectionMode.explicit) {
        final models = await txn.query(
          'ai_model_configs',
          where: 'model_config_id = ?',
          whereArgs: [selection.modelConfigId],
          limit: 1,
        );
        if (models.isEmpty) throw StateError('AI_SELECTED_MODEL_NOT_FOUND');
        final model = AiModelConfig.fromDatabaseRow(models.single);
        if (model.taskKind != selection.taskKind) {
          throw StateError('AI_SELECTED_MODEL_TASK_KIND_MISMATCH');
        }
        if (!model.enabled) throw StateError('AI_SELECTED_MODEL_DISABLED');

        if (model.runtimeKind == AiRuntimeKind.cloud) {
          final providers = await txn.query(
            'ai_provider_configs',
            columns: ['enabled'],
            where: 'provider_id = ?',
            whereArgs: [model.providerId],
            limit: 1,
          );
          if (providers.isEmpty) {
            throw StateError('AI_SELECTED_MODEL_PROVIDER_NOT_FOUND');
          }
          if (providers.single['enabled'] != 1) {
            throw StateError('AI_SELECTED_MODEL_PROVIDER_DISABLED');
          }
        } else {
          final assets = await txn.query(
            'ai_local_model_assets',
            columns: ['install_status'],
            where: 'local_asset_id = ?',
            whereArgs: [model.localAssetId],
            limit: 1,
          );
          if (assets.isEmpty) throw StateError('AI_SELECTED_MODEL_ASSET_NOT_FOUND');
          if (assets.single['install_status'] != 'installed') {
            throw StateError('AI_SELECTED_MODEL_ASSET_NOT_INSTALLED');
          }
        }
      }

      final row = selection.toDatabaseRow();
      row['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await txn.insert(
        'ai_task_model_selections',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
