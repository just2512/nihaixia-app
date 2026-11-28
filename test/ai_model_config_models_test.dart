import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_model_config.dart';
import 'package:nihaisha_app/models/ai_provider_config.dart';
import 'package:nihaisha_app/models/ai_task_model_selection.dart';

void main() {
  group('AiProviderConfig', () {
    test('accepts HTTPS and stores only an opaque credential reference', () {
      final config = AiProviderConfig(
        providerId: 'provider-1',
        displayName: 'Example',
        protocolAdapterId: 'openai-chat-completions-v1',
        baseUrl: 'https://api.example.test/v1',
        credentialRef: 'credential-ref-1',
      );
      final row = config.toDatabaseRow();
      expect(row['credential_ref'], 'credential-ref-1');
      expect(row.containsKey('api_key'), isFalse);
      expect(row.containsKey('secret'), isFalse);
    });

    test('rejects HTTP, user-info, query and fragment URL components', () {
      for (final url in [
        'http://api.example.test/v1',
        'https://user:password@api.example.test/v1',
        'https://api.example.test/v1?key=value',
        'https://api.example.test/v1#fragment',
      ]) {
        expect(
          () => AiProviderConfig(
            providerId: 'provider-1',
            displayName: 'Example',
            protocolAdapterId: 'adapter-v1',
            baseUrl: url,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    });
  });

  group('AiModelConfig', () {
    test('requires task-specific generative model budgets', () {
      expect(
        () => AiModelConfig(
          modelConfigId: 'text-1',
          displayName: 'Text model',
          taskKind: AiTaskKind.textReasoning,
          runtimeKind: AiRuntimeKind.cloud,
          modelIdentifier: 'provider-model',
          providerId: 'provider-1',
          apiProtocolId: 'chat-v1',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects output budget equal to context window', () {
      expect(
        () => AiModelConfig(
          modelConfigId: 'text-1',
          displayName: 'Text model',
          taskKind: AiTaskKind.textReasoning,
          runtimeKind: AiRuntimeKind.cloud,
          modelIdentifier: 'provider-model',
          providerId: 'provider-1',
          apiProtocolId: 'chat-v1',
          contextWindowTokens: 8192,
          maxOutputTokens: 8192,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('requires Embedding dimension, normalization and batch limits', () {
      expect(
        () => AiModelConfig(
          modelConfigId: 'embedding-1',
          displayName: 'Embedding',
          taskKind: AiTaskKind.embedding,
          runtimeKind: AiRuntimeKind.cloud,
          modelIdentifier: 'embedding-model',
          providerId: 'provider-1',
          apiProtocolId: 'embeddings-v1',
          maxInputTokens: 512,
          maxBatchItems: 16,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final model = AiModelConfig(
        modelConfigId: 'embedding-1',
        displayName: 'Embedding',
        taskKind: AiTaskKind.embedding,
        runtimeKind: AiRuntimeKind.cloud,
        modelIdentifier: 'embedding-model',
        providerId: 'provider-1',
        apiProtocolId: 'embeddings-v1',
        maxInputTokens: 512,
        maxBatchItems: 16,
        embeddingDimension: 384,
        embeddingNormalization: 'l2',
      );
      expect(model.embeddingDimension, 384);
    });

    test('requires Reranker candidate limit and ordered-ID protocol', () {
      expect(
        () => AiModelConfig(
          modelConfigId: 'reranker-1',
          displayName: 'Reranker',
          taskKind: AiTaskKind.reranking,
          runtimeKind: AiRuntimeKind.cloud,
          modelIdentifier: 'rerank-model',
          providerId: 'provider-1',
          apiProtocolId: 'rerank-v1',
          maxInputTokens: 4096,
          maxCandidates: 20,
          maxCandidateTokens: 256,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final model = AiModelConfig(
        modelConfigId: 'reranker-1',
        displayName: 'Reranker',
        taskKind: AiTaskKind.reranking,
        runtimeKind: AiRuntimeKind.cloud,
        modelIdentifier: 'rerank-model',
        providerId: 'provider-1',
        apiProtocolId: 'rerank-v1',
        maxInputTokens: 4096,
        maxCandidates: 20,
        maxCandidateTokens: 256,
        outputProtocolId: 'ordered-candidate-ids-v1',
      );
      expect(model.outputProtocolId, 'ordered-candidate-ids-v1');
    });

    test('local model requires localAssetId and rejects provider fields', () {
      expect(
        () => AiModelConfig(
          modelConfigId: 'local-text',
          displayName: 'Local text',
          taskKind: AiTaskKind.textReasoning,
          runtimeKind: AiRuntimeKind.local,
          modelIdentifier: 'local-model',
          providerId: 'provider-1',
          contextWindowTokens: 4096,
          maxOutputTokens: 512,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AiTaskModelSelection', () {
    test('text reasoning requires an explicit model', () {
      expect(
        AiTaskModelSelection(
          taskKind: AiTaskKind.textReasoning,
          selectionMode: AiTaskModelSelectionMode.explicit,
          modelConfigId: 'text-1',
        ).selectionMode,
        AiTaskModelSelectionMode.explicit,
      );
      expect(
        () => AiTaskModelSelection(
          taskKind: AiTaskKind.textReasoning,
          selectionMode: AiTaskModelSelectionMode.deterministicUnconfigured,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('only image and audio may inherit text reasoning', () {
      for (final task in [
        AiTaskKind.imageUnderstanding,
        AiTaskKind.audioUnderstanding,
      ]) {
        expect(
          AiTaskModelSelection(
            taskKind: task,
            selectionMode: AiTaskModelSelectionMode.inheritTextReasoning,
          ).selectionMode,
          AiTaskModelSelectionMode.inheritTextReasoning,
        );
      }
      for (final task in [AiTaskKind.embedding, AiTaskKind.reranking]) {
        expect(
          () => AiTaskModelSelection(
            taskKind: task,
            selectionMode: AiTaskModelSelectionMode.inheritTextReasoning,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test('Embedding and Reranker can remain deterministic when unconfigured',
        () {
      for (final task in [AiTaskKind.embedding, AiTaskKind.reranking]) {
        expect(
          AiTaskModelSelection(
            taskKind: task,
            selectionMode:
                AiTaskModelSelectionMode.deterministicUnconfigured,
          ).selectionMode,
          AiTaskModelSelectionMode.deterministicUnconfigured,
        );
      }
    });
  });
}
