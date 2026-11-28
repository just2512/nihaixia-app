import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/ai_model_config_repository.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/models/ai_local_model_asset.dart';
import 'package:nihaisha_app/models/ai_model_config.dart';
import 'package:nihaisha_app/models/ai_provider_config.dart';
import 'package:nihaisha_app/models/ai_task_model_selection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late AiModelConfigRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-model-config-db-');
    DatabaseHelper.configureTestDatabase(
      'ai-model-config.db',
      factory: databaseFactoryFfi,
      directoryPath: directory.path,
    );
    repository = AiModelConfigRepository();
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<AiLocalModelAsset> saveEmbeddingAsset() async {
    final asset = AiLocalModelAsset(
      localAssetId: 'asset-embedding-1',
      modelIdentifier: 'local-embedding-model',
      taskKind: AiTaskKind.embedding,
      runtimeAdapterId: 'runtime-adapter-v1',
      modelFormat: 'tflite',
      privateRelativePath: 'ai_models/embedding/model.tflite',
      byteLength: 1024,
      sha256: List.filled(64, 'a').join(),
      manifestJson: '{"schema":1}',
      installStatus: 'installed',
      maxInputTokens: 512,
      embeddingDimension: 384,
      embeddingNormalization: 'l2',
      maxBatchItems: 16,
      tokenizerId: 'tokenizer-1',
      tokenizerRevision: 'rev-1',
    );
    await repository.saveLocalAsset(asset);
    return asset;
  }

  AiModelConfig cloudTextModel() => AiModelConfig(
        modelConfigId: 'cloud-text-1',
        displayName: 'Cloud text',
        taskKind: AiTaskKind.textReasoning,
        runtimeKind: AiRuntimeKind.cloud,
        modelIdentifier: 'chat-model-id',
        providerId: 'provider-1',
        apiProtocolId: 'chat-completions-v1',
        contextWindowTokens: 32768,
        maxOutputTokens: 4096,
        tokenizerId: 'provider-tokenizer',
        tokenizerRevision: 'rev-1',
      );

  test('creates schema v9 tables without API key columns', () async {
    final db = await DatabaseHelper.instance.database;
    expect(await db.getVersion(), 9);
    for (final table in [
      'ai_provider_configs',
      'ai_local_model_assets',
      'ai_model_configs',
      'ai_task_model_selections',
    ]) {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      expect(rows, hasLength(1), reason: '$table must exist');
    }
    final columns = await db.rawQuery('PRAGMA table_info(ai_provider_configs)');
    final names = columns.map((row) => row['name']).toSet();
    expect(names, contains('credential_ref'));
    expect(names, isNot(contains('api_key')));
    expect(names, isNot(contains('secret')));
  });

  test('persists Provider and Cloud Model using an opaque credentialRef',
      () async {
    await repository.saveProvider(
      AiProviderConfig(
        providerId: 'provider-1',
        displayName: 'Provider',
        protocolAdapterId: 'chat-completions-v1',
        baseUrl: 'https://api.example.test/v1',
        credentialRef: 'credential-ref-1',
      ),
    );
    await repository.saveModelConfig(cloudTextModel());
    await repository.saveTaskSelection(
      AiTaskModelSelection(
        taskKind: AiTaskKind.textReasoning,
        selectionMode: AiTaskModelSelectionMode.explicit,
        modelConfigId: 'cloud-text-1',
      ),
    );

    expect(
      (await repository.getProvider('provider-1'))?.credentialRef,
      'credential-ref-1',
    );
    expect(
      (await repository.getModelConfig('cloud-text-1'))?.modelIdentifier,
      'chat-model-id',
    );
    expect(
      (await repository.getTaskSelection(AiTaskKind.textReasoning))
          ?.modelConfigId,
      'cloud-text-1',
    );
  });

  test('persists local Embedding as a distinct task/runtime configuration',
      () async {
    final asset = await saveEmbeddingAsset();
    await repository.saveModelConfig(
      AiModelConfig(
        modelConfigId: 'local-embedding-1',
        displayName: 'Local embedding',
        taskKind: AiTaskKind.embedding,
        runtimeKind: AiRuntimeKind.local,
        modelIdentifier: asset.modelIdentifier,
        localAssetId: asset.localAssetId,
        modelFingerprint: asset.sha256,
        maxInputTokens: 512,
        embeddingDimension: 384,
        embeddingNormalization: 'l2',
        maxBatchItems: 16,
        tokenizerId: asset.tokenizerId,
        tokenizerRevision: asset.tokenizerRevision,
      ),
    );
    await repository.saveTaskSelection(
      AiTaskModelSelection(
        taskKind: AiTaskKind.embedding,
        selectionMode: AiTaskModelSelectionMode.explicit,
        modelConfigId: 'local-embedding-1',
      ),
    );

    final saved = await repository.getModelConfig('local-embedding-1');
    expect(saved?.taskKind, AiTaskKind.embedding);
    expect(saved?.runtimeKind, AiRuntimeKind.local);
    expect(saved?.embeddingDimension, 384);
    expect(
      (await repository.listLocalAssets()).single.localAssetId,
      asset.localAssetId,
    );
  });

  test('keeps referenced local asset identity immutable', () async {
    final asset = await saveEmbeddingAsset();
    await repository.saveModelConfig(
      AiModelConfig(
        modelConfigId: 'local-embedding-1',
        displayName: 'Local embedding',
        taskKind: AiTaskKind.embedding,
        runtimeKind: AiRuntimeKind.local,
        modelIdentifier: asset.modelIdentifier,
        localAssetId: asset.localAssetId,
        modelFingerprint: asset.sha256,
        maxInputTokens: 512,
        embeddingDimension: 384,
        embeddingNormalization: 'l2',
        maxBatchItems: 16,
        tokenizerId: 'tokenizer-1',
        tokenizerRevision: 'rev-1',
      ),
    );

    final replacement = AiLocalModelAsset(
      localAssetId: asset.localAssetId,
      modelIdentifier: asset.modelIdentifier,
      taskKind: asset.taskKind,
      runtimeAdapterId: asset.runtimeAdapterId,
      modelFormat: asset.modelFormat,
      privateRelativePath: asset.privateRelativePath,
      byteLength: asset.byteLength,
      sha256: List.filled(64, 'b').join(),
      manifestJson: '{"schema":1,"revision":"replacement"}',
      installStatus: 'installed',
      maxInputTokens: 512,
      embeddingDimension: 768,
      embeddingNormalization: 'l2',
      maxBatchItems: 16,
      tokenizerId: 'tokenizer-1',
      tokenizerRevision: 'rev-1',
    );

    await expectLater(
      repository.saveLocalAsset(replacement),
      throwsA(isA<StateError>()),
    );
    expect(
      (await repository.getLocalAsset(asset.localAssetId))?.sha256,
      asset.sha256,
    );

    // Operational status can change without changing the model identity.
    final missing = AiLocalModelAsset(
      localAssetId: asset.localAssetId,
      modelIdentifier: asset.modelIdentifier,
      taskKind: asset.taskKind,
      runtimeAdapterId: asset.runtimeAdapterId,
      modelFormat: asset.modelFormat,
      privateRelativePath: asset.privateRelativePath,
      byteLength: asset.byteLength,
      sha256: asset.sha256,
      manifestJson: asset.manifestJson,
      installStatus: 'missing',
      maxInputTokens: 512,
      embeddingDimension: 384,
      embeddingNormalization: 'l2',
      maxBatchItems: 16,
      tokenizerId: 'tokenizer-1',
      tokenizerRevision: 'rev-1',
    );
    await repository.saveLocalAsset(missing);
    expect(
      (await repository.getLocalAsset(asset.localAssetId))?.installStatus,
      'missing',
    );
  });

  test('validates Local ModelConfig against its referenced asset metadata',
      () async {
    final asset = await saveEmbeddingAsset();

    AiModelConfig localEmbedding({
      String? modelIdentifier,
      String? modelFingerprint,
      int embeddingDimension = 384,
      String embeddingNormalization = 'l2',
      String? tokenizerId = 'tokenizer-1',
      String? tokenizerRevision = 'rev-1',
      int maxInputTokens = 512,
      int maxBatchItems = 16,
      bool omitFingerprint = false,
    }) =>
        AiModelConfig(
          modelConfigId: 'local-embedding-validation',
          displayName: 'Local embedding validation',
          taskKind: AiTaskKind.embedding,
          runtimeKind: AiRuntimeKind.local,
          modelIdentifier: modelIdentifier ?? asset.modelIdentifier,
          localAssetId: asset.localAssetId,
          modelFingerprint: omitFingerprint ? null : (modelFingerprint ?? asset.sha256),
          maxInputTokens: maxInputTokens,
          embeddingDimension: embeddingDimension,
          embeddingNormalization: embeddingNormalization,
          maxBatchItems: maxBatchItems,
          tokenizerId: tokenizerId,
          tokenizerRevision: tokenizerRevision,
        );

    await expectLater(
      repository.saveModelConfig(
        localEmbedding(modelIdentifier: 'different-model-id'),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(localEmbedding(omitFingerprint: true)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(localEmbedding(embeddingDimension: 768)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(
        localEmbedding(embeddingNormalization: 'none'),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(localEmbedding(tokenizerId: 'other-tokenizer')),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(localEmbedding(maxInputTokens: 1024)),
      throwsA(isA<StateError>()),
    );
  });

  test('validates Local Reranker metadata against its referenced asset',
      () async {
    final asset = AiLocalModelAsset(
      localAssetId: 'asset-reranker-1',
      modelIdentifier: 'local-reranker-model',
      taskKind: AiTaskKind.reranking,
      runtimeAdapterId: 'reranker-runtime-v1',
      modelFormat: 'tflite',
      privateRelativePath: 'ai_models/reranker/model.tflite',
      byteLength: 2048,
      sha256: List.filled(64, 'c').join(),
      manifestJson: '{"schema":1}',
      installStatus: 'installed',
      maxInputTokens: 4096,
      maxCandidates: 20,
      outputProtocolId: 'ordered-candidate-ids-v1',
      tokenizerId: 'reranker-tokenizer',
      tokenizerRevision: 'rev-1',
    );
    await repository.saveLocalAsset(asset);

    AiModelConfig localReranker({
      int maxCandidates = 20,
      String outputProtocolId = 'ordered-candidate-ids-v1',
      int maxInputTokens = 4096,
      String? modelIdentifier,
    }) =>
        AiModelConfig(
          modelConfigId: 'local-reranker-validation',
          displayName: 'Local reranker validation',
          taskKind: AiTaskKind.reranking,
          runtimeKind: AiRuntimeKind.local,
          modelIdentifier: modelIdentifier ?? asset.modelIdentifier,
          localAssetId: asset.localAssetId,
          modelFingerprint: asset.sha256,
          maxInputTokens: maxInputTokens,
          maxCandidates: maxCandidates,
          maxCandidateTokens: 256,
          outputProtocolId: outputProtocolId,
          tokenizerId: 'reranker-tokenizer',
          tokenizerRevision: 'rev-1',
        );

    await repository.saveModelConfig(localReranker());
    await repository.deleteModelConfig('local-reranker-validation');
    await expectLater(
      repository.saveModelConfig(localReranker(maxCandidates: 40)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(
        localReranker(outputProtocolId: 'free-form-scores-v1'),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(localReranker(maxInputTokens: 8192)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.saveModelConfig(
        localReranker(modelIdentifier: 'different-reranker'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('blocks deletion while Provider, Model or Asset is referenced', () async {
    await repository.saveProvider(
      AiProviderConfig(
        providerId: 'provider-1',
        displayName: 'Provider',
        protocolAdapterId: 'chat-v1',
        baseUrl: 'https://api.example.test/v1',
      ),
    );
    await repository.saveModelConfig(cloudTextModel());
    await repository.saveTaskSelection(
      AiTaskModelSelection(
        taskKind: AiTaskKind.textReasoning,
        selectionMode: AiTaskModelSelectionMode.explicit,
        modelConfigId: 'cloud-text-1',
      ),
    );

    await expectLater(
      repository.deleteProvider('provider-1'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.deleteModelConfig('cloud-text-1'),
      throwsA(isA<StateError>()),
    );

    await repository.saveModelConfig(
      AiModelConfig(
        modelConfigId: 'cloud-text-unselected',
        displayName: 'Unselected cloud text',
        taskKind: AiTaskKind.textReasoning,
        runtimeKind: AiRuntimeKind.cloud,
        modelIdentifier: 'chat-model-unselected',
        providerId: 'provider-1',
        apiProtocolId: 'chat-completions-v1',
        contextWindowTokens: 8192,
        maxOutputTokens: 1024,
      ),
    );
    // An unselected model can be deleted without changing the active selection.
    await repository.deleteModelConfig('cloud-text-unselected');
    final asset = await saveEmbeddingAsset();
    await repository.saveModelConfig(
      AiModelConfig(
        modelConfigId: 'local-embedding-1',
        displayName: 'Local embedding',
        taskKind: AiTaskKind.embedding,
        runtimeKind: AiRuntimeKind.local,
        modelIdentifier: asset.modelIdentifier,
        localAssetId: asset.localAssetId,
        modelFingerprint: asset.sha256,
        maxInputTokens: 512,
        embeddingDimension: 384,
        embeddingNormalization: 'l2',
        maxBatchItems: 16,
        tokenizerId: asset.tokenizerId,
        tokenizerRevision: asset.tokenizerRevision,
      ),
    );
    await expectLater(
      repository.deleteLocalAsset(asset.localAssetId),
      throwsA(isA<StateError>()),
    );
  });

  test('validates model kind and requires text selection for inheritance',
      () async {
    await repository.saveProvider(
      AiProviderConfig(
        providerId: 'provider-1',
        displayName: 'Provider',
        protocolAdapterId: 'chat-v1',
        baseUrl: 'https://api.example.test/v1',
      ),
    );

    await expectLater(
      repository.saveTaskSelection(
        AiTaskModelSelection(
          taskKind: AiTaskKind.imageUnderstanding,
          selectionMode: AiTaskModelSelectionMode.inheritTextReasoning,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    await repository.saveModelConfig(cloudTextModel());
    await repository.saveTaskSelection(
      AiTaskModelSelection(
        taskKind: AiTaskKind.textReasoning,
        selectionMode: AiTaskModelSelectionMode.explicit,
        modelConfigId: 'cloud-text-1',
      ),
    );
    await repository.saveTaskSelection(
      AiTaskModelSelection(
        taskKind: AiTaskKind.imageUnderstanding,
        selectionMode: AiTaskModelSelectionMode.inheritTextReasoning,
      ),
    );
    expect(
      (await repository.getTaskSelection(AiTaskKind.imageUnderstanding))
          ?.selectionMode,
      AiTaskModelSelectionMode.inheritTextReasoning,
    );

    await expectLater(
      repository.saveTaskSelection(
        AiTaskModelSelection(
          taskKind: AiTaskKind.reranking,
          selectionMode: AiTaskModelSelectionMode.explicit,
          modelConfigId: 'cloud-text-1',
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('represents legacy E4B asset without claiming it is loaded', () async {
    final asset = AiLocalModelAsset(
      localAssetId: 'legacy-e4b-fixed-model',
      modelIdentifier: 'gemma-4-E4B-it',
      taskKind: AiTaskKind.textReasoning,
      assetSource: 'legacy_native',
      runtimeAdapterId: 'litert-lm-e4b-native',
      modelFormat: 'litertlm',
      privateRelativePath: 'ai_models/gemma-4-E4B-it.litertlm',
      byteLength: 3659530240,
      sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
      manifestJson: '{"compatibility":"legacy-e4b-native"}',
      installStatus: 'unknown',
      contextWindowTokens: 8192,
      maxOutputTokens: 1024,
      modelRevision: '28299f30ee4d43294517a4ac93abd6163412f07f',
    );
    await repository.saveLocalAsset(asset);
    await repository.saveModelConfig(
      AiModelConfig(
        modelConfigId: 'legacy-e4b-text',
        displayName: 'Gemma 4 E4B (existing Native runtime)',
        taskKind: AiTaskKind.textReasoning,
        runtimeKind: AiRuntimeKind.local,
        modelIdentifier: asset.modelIdentifier,
        localAssetId: asset.localAssetId,
        modelFingerprint: asset.sha256,
        modelRevision: asset.modelRevision,
        contextWindowTokens: 8192,
        maxOutputTokens: 1024,
        enabled: false,
      ),
    );

    final saved = await repository.getLocalAsset(asset.localAssetId);
    expect(saved?.assetSource, 'legacy_native');
    expect(saved?.installStatus, 'unknown');
    expect((await repository.getModelConfig('legacy-e4b-text'))?.enabled, isFalse);
  });

  test('migrates v8 to v9 and preserves data across rollback/re-upgrade',
      () async {
    final legacyPath = directory.path + '/legacy.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE user_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('user_settings', {
            'key': 'migration-sentinel',
            'value': 'preserve-me',
          });
        },
      ),
    );
    await legacy.close();

    DatabaseHelper.configureTestDatabase(
      'legacy.db',
      factory: databaseFactoryFfi,
      directoryPath: directory.path,
    );
    final upgraded = await DatabaseHelper.instance.database;
    expect(await upgraded.getVersion(), 9);
    expect(
      (await upgraded.query(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['migration-sentinel'],
      )).single['value'],
      'preserve-me',
    );
    final tables = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'ai_%'",
    );
    expect(
      tables.map((row) => row['name']).toSet(),
      containsAll([
        'ai_provider_configs',
        'ai_local_model_assets',
        'ai_model_configs',
        'ai_task_model_selections',
      ]),
    );
    await upgraded.insert('ai_provider_configs', {
      'provider_id': 'migration-provider',
      'display_name': 'Migration Provider',
      'protocol_adapter_id': 'chat-completions-v1',
      'base_url': 'https://example.test/v1',
      'credential_ref': 'aicred:v1:opaque-migration-reference',
      'enabled': 1,
      'created_at': '2026-11-28T00:00:00.000Z',
      'updated_at': '2026-11-28T00:00:00.000Z',
      'config_schema_version': 1,
    });
    await DatabaseHelper.closeTestDatabase();

    // Simulate opening the v9 database with an older v8 app. The old app does
    // not know these tables and must leave them and their rows untouched.
    final rolledBack = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(version: 8),
    );
    expect(await rolledBack.getVersion(), 8);
    expect(
      (await rolledBack.query(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['migration-sentinel'],
      )).single['value'],
      'preserve-me',
    );
    expect(
      (await rolledBack.query(
        'ai_provider_configs',
        where: 'provider_id = ?',
        whereArgs: ['migration-provider'],
      )),
      hasLength(1),
    );
    await rolledBack.close();

    // Re-upgrading must be idempotent: CREATE TABLE/INDEX IF NOT EXISTS keeps
    // the v9 rows instead of failing on objects left by the v8 app.
    DatabaseHelper.configureTestDatabase(
      'legacy.db',
      factory: databaseFactoryFfi,
      directoryPath: directory.path,
    );
    final reupgraded = await DatabaseHelper.instance.database;
    expect(await reupgraded.getVersion(), 9);
    expect(
      (await reupgraded.query(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['migration-sentinel'],
      )).single['value'],
      'preserve-me',
    );
    expect(
      (await reupgraded.query(
        'ai_provider_configs',
        where: 'provider_id = ?',
        whereArgs: ['migration-provider'],
      )),
      hasLength(1),
    );
  });
}
