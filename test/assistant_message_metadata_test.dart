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
      reasoningRequestId: 'abcdef0123456789abcdef0123456789',
      invocationOrigin: 'aiDispatch',
      contextRef: const {
        'kind': 'classic',
        'moduleId': 'shanghan',
        'anchorId': 'shanghan:clause:002',
        'anchorVersion': 'sha256:abc123',
        'sourceId': 'asset:assets/shanghan/clause_001.md',
        'selectedText': '发热，汗出，恶风',
      },
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
    expect(restored.reasoningRequestId, 'abcdef0123456789abcdef0123456789');
    expect(restored.invocationOrigin, 'aiDispatch');
    expect(restored.contextRef, {
      'kind': 'classic',
      'moduleId': 'shanghan',
      'anchorId': 'shanghan:clause:002',
      'anchorVersion': 'sha256:abc123',
      'sourceId': 'asset:assets/shanghan/clause_001.md',
      'selectedText': '发热，汗出，恶风',
    });
  });

  test('field context path and snapshot survive message history metadata', () {
    const contextRef = {
      'kind': 'field',
      'moduleId': 'ziwei',
      'anchorId':
          'ziwei:result:snapshot-a:field:palacesByPhysicalBranch.0.stars',
      'anchorVersion': 'snapshot-a',
      'snapshotId': 'snapshot-a',
      'ruleVersion': 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      'fieldPath': 'palacesByPhysicalBranch.0.stars',
      'sourceId': 'local-engine:ziwei-core@0.13.0',
    };
    const original = AssistantMessageMetadata(contextRef: contextRef);

    final restored = AssistantMessageMetadata.decode(original.encode());
    expect(restored.contextRef, contextRef);
  });

  test('multi-tool plan step provenance round-trips in typed metadata', () {
    const original = AssistantMessageMetadata(
      traceId: '0123456789abcdef0123456789abcdef',
      invocationOrigin: 'aiDispatch',
      toolStatus: 'PLAN_SUCCEEDED',
      sourceIds: [
        'local-knowledge:yuxiaji',
        'local-knowledge:sanshan',
      ],
      toolPlanSteps: [
        AssistantToolPlanStepMetadata(
          toolId: 'yuxiaji_omen',
          capabilityId: 'yuxiaji_omen',
          title: '玉匣灵兆',
          status: 'SUCCEEDED',
          arguments: {'time': 'local-device'},
          sourceIds: ['local-knowledge:yuxiaji'],
        ),
        AssistantToolPlanStepMetadata(
          toolId: 'sanshan_lingqian',
          capabilityId: 'sanshan_lingqian',
          title: '三山灵签',
          status: 'SUCCEEDED',
          sourceIds: ['local-knowledge:sanshan'],
        ),
      ],
    );

    final restored = AssistantMessageMetadata.decode(original.encode());

    expect(restored.toolPlanSteps, hasLength(2));
    expect(restored.toolPlanSteps.first.toolId, 'yuxiaji_omen');
    expect(restored.toolPlanSteps.first.capabilityId, 'yuxiaji_omen');
    expect(restored.toolPlanSteps.first.arguments, {'time': 'local-device'});
    expect(restored.toolPlanSteps.first.sourceIds, ['local-knowledge:yuxiaji']);
    expect(restored.toolPlanSteps.last.status, 'SUCCEEDED');
    expect(restored.invocationOrigin, 'aiDispatch');
    expect(restored.toolStatus, 'PLAN_SUCCEEDED');
  });

  test('malformed plan metadata entries are ignored without breaking history decode', () {
    final restored = AssistantMessageMetadata.decode('''
      {
        "schemaVersion": 1,
        "toolPlanSteps": [
          {"toolId":"valid","capabilityId":"valid","title":"有效","status":"SUCCEEDED"},
          {"toolId":42,"capabilityId":"bad","title":"错误","status":"SUCCEEDED"},
          "not-an-object"
        ]
      }
    ''');

    expect(restored.toolPlanSteps, hasLength(1));
    expect(restored.toolPlanSteps.single.toolId, 'valid');
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
    expect(restored.invocationOrigin, isNull);
    expect(restored.contextRef, isEmpty);
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
