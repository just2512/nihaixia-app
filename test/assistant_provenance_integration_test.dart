import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupunctureRepository.load();
    await AcupointRepository.load();
  });

  test('知识来源、已校验工具参数和执行结果可由统一消息契约恢复', () async {
    final knowledge = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '桂枝汤',
    );

    expect(knowledge.sources, isNotEmpty);
    expect(knowledge.sourceIds, isNotEmpty);
    expect(knowledge.sourceIds.toSet().length, knowledge.sourceIds.length);
    expect(
      knowledge.sources.every((source) =>
          source.sourceId.isNotEmpty &&
          source.localBacklink.isNotEmpty &&
          source.locatorStatus != 'VERIFIED'),
      isTrue,
    );
    expect(
      knowledge.sources.any((source) => source.sourceKind == 'formula'),
      isTrue,
    );
    expect(
      knowledge.sources.any((source) => source.sourceKind == 'medical_case'),
      isTrue,
    );

    final knowledgeMetadata = AssistantMessageMetadata(
      mode: 'learning',
      selectedMode: 'automatic',
      sourceIds: knowledge.sourceIds,
    );
    final restoredKnowledge = AssistantMessageMetadata.decode(
      knowledgeMetadata.encode(),
    );
    expect(restoredKnowledge.sourceIds, knowledge.sourceIds);

    final toolResult = AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: const {'推算日期': '2026-11-07'},
      arguments: const {'date': '2026-11-07'},
      sourceIds: const ['local-engine:yunqi:v1'],
    );
    expect(toolResult.validateFor('yunqi'), isEmpty);
    expect(
      toolResult.toConversationText(),
      contains('执行参数：date=2026-11-07'),
    );

    final toolMetadata = AssistantMessageMetadata(
      mode: 'tools',
      selectedMode: 'automatic',
      toolId: toolResult.toolId,
      toolStatus: toolResult.statusLabel,
      sourceIds: toolResult.sourceIds,
      toolArguments: toolResult.arguments,
    );
    final restoredTool = AssistantMessageMetadata.decode(toolMetadata.encode());
    expect(restoredTool.toolId, 'yunqi');
    expect(restoredTool.toolStatus, 'SUCCEEDED');
    expect(restoredTool.toolArguments, {'date': '2026-11-07'});
    expect(restoredTool.sourceIds, ['local-engine:yunqi:v1']);
  });
}
