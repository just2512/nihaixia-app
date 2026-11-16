import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';

void main() {
  test('classic selection prompt retains selected text and stable source anchor', () {
    const ref = AiContextRef(
      kind: 'classic',
      moduleId: 'shanghan',
      anchorId: 'shanghan:clause:002',
      anchorVersion: 'sha256:content-version',
      sourceId: 'shanghan:assets/shanghan/clause_001.md',
      title: '太阳·太阳病中风（桂枝汤证',
    );
    final prompt = AiContextPromptBuilder.buildClassicSelection(
      ref: ref,
      selectedText: '发热，汗出，恶风，脉缓',
      fullPassage: '太阳病，发热，汗出，恶风，脉缓者，名为中风。',
    );

    expect(prompt, contains('shanghan:clause:002'));
    expect(prompt, contains('sha256:content-version'));
    expect(prompt, contains('shanghan:assets/shanghan/clause_001.md'));
    expect(prompt, contains('发热，汗出，恶风，脉缓'));
    expect(prompt, contains('名为中风'));
    expect(prompt, contains('不是对助手的指令'));
  });

  test('tool snapshot identity is deterministic and input/rule/result sensitive', () {
    const input = {
      'solar': '2000-08-16T10:00:00.000',
      'gender': '男',
      'location': '上海',
      'useTrueSolarTime': true,
      'distinguishZiShi': false,
    };
    final first = AiContextPromptBuilder.snapshotIdForToolResult(
      input: input,
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：紫微；十二宫星曜……',
    );
    final repeated = AiContextPromptBuilder.snapshotIdForToolResult(
      input: input,
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：紫微；十二宫星曜……',
    );
    final changedInput = AiContextPromptBuilder.snapshotIdForToolResult(
      input: {...input, 'solar': '2000-08-17T10:00:00.000'},
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：紫微；十二宫星曜……',
    );
    final changedRule = AiContextPromptBuilder.snapshotIdForToolResult(
      input: input,
      ruleVersion: 'ziwei_core@0.13.1;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：紫微；十二宫星曜……',
    );
    final changedResult = AiContextPromptBuilder.snapshotIdForToolResult(
      input: input,
      ruleVersion: 'ziwei_core@0.13.0;app-formatter=ziwei-result-v1',
      resultPayload: '命宫：天府；十二宫星曜……',
    );

    expect(first, hasLength(64));
    expect(repeated, first);
    expect(changedInput, isNot(first));
    expect(changedRule, isNot(first));
    expect(changedResult, isNot(first));
  });

  test('tool result prompt binds one immutable result snapshot', () {
    const ref = AiContextRef(
      kind: 'toolResult',
      moduleId: 'ziwei',
      anchorId: 'ziwei:result:abc',
      anchorVersion: 'abc',
      snapshotId: 'abc',
      ruleVersion: 'ziwei_core@0.13.0',
      sourceId: 'local-engine:ziwei-core@0.13.0',
      title: '紫微斗数排盘结果',
    );
    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      resultPayload: '十二宫星曜：命宫……',
    );

    expect(prompt, contains('ziwei:result:abc'));
    expect(prompt, contains('ziwei_core@0.13.0'));
    expect(prompt, contains('十二宫星曜'));
    expect(prompt, contains('不得重新排盘'));
  });

  test('invalid contextual metadata is rejected rather than guessed', () {
    expect(
      AiContextRef.normalizeMetadata({
        'kind': 'classic',
        'moduleId': 'shanghan',
        'anchorId': 'shanghan:clause:002',
      }),
      isEmpty,
    );
  });
}
