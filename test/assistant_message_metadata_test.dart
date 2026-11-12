import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';

void main() {
  test('versioned message metadata round-trips tool and source context', () {
    const original = AssistantMessageMetadata(
      mode: 'tools',
      selectedMode: 'automatic',
      toolId: 'yunqi',
      toolChoicePending: true,
      replayable: false,
      attachmentType: 'image',
      tcmTaskId: 'task-42',
      toolStatus: 'SUCCEEDED',
      sourceIds: ['local-engine:yunqi'],
      toolArguments: {'date': '2026-11-06'},
      knowledgeStatus: 'RETRIEVED',
      traceId: '0123456789abcdef0123456789abcdef',
    );
    final restored = AssistantMessageMetadata.decode(original.encode());
    expect(restored.mode, 'tools');
    expect(restored.selectedMode, 'automatic');
    expect(restored.toolId, 'yunqi');
    expect(restored.toolChoicePending, isTrue);
    expect(restored.replayable, isFalse);
    expect(restored.attachmentType, 'image');
    expect(restored.tcmTaskId, 'task-42');
    expect(restored.toolStatus, 'SUCCEEDED');
    expect(restored.sourceIds, ['local-engine:yunqi']);
    expect(restored.toolArguments, {'date': '2026-11-06'});
    expect(restored.knowledgeStatus, 'RETRIEVED');
    expect(restored.traceId, '0123456789abcdef0123456789abcdef');
  });

  test('legacy semicolon metadata remains readable', () {
    final restored = AssistantMessageMetadata.decode(
      'mode=consultation;selectedMode=learning;tool=yunqi;'
      'tool_choice=true;replayable=false;attachment=image;tcm_task=task-7',
    );
    expect(restored.mode, 'consultation');
    expect(restored.selectedMode, 'learning');
    expect(restored.toolId, 'yunqi');
    expect(restored.toolChoicePending, isTrue);
    expect(restored.replayable, isFalse);
    expect(restored.attachmentType, 'image');
    expect(restored.tcmTaskId, 'task-7');
    expect(restored.traceId, isNull);
  });

  test('empty or unknown metadata safely falls back to default state', () {
    final empty = AssistantMessageMetadata.decode('');
    final unknown = AssistantMessageMetadata.decode('{"schemaVersion":99}');
    expect(empty.mode, isNull);
    expect(empty.toolId, isNull);
    expect(empty.replayable, isTrue);
    expect(unknown.mode, isNull);
    expect(unknown.replayable, isTrue);
  });
}
