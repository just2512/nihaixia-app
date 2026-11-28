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
        maxInputTokens: 512,
        embeddingDimension: 384,
        embeddingNormalization: 'l2',
        maxBatchItems: 16,
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

  test('migrates schema v8 to v9 and preserves existing user settings',
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
    final rows = await upgraded.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['migration-sentinel'],
    );
    expect(rows.single['value'], 'preserve-me');
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
  });
}
