import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';

void main() {
  test('typed tool result preserves fields and marks missing values explicitly', () {
    const result = AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: {
        '推算日期': '2026-11-06',
        '司天': '少阳相火',
        '岁运病候': '',
      },
      disclaimer: '仅供理论学习。',
      arguments: {'date': '2026-11-06'},
    );

    final text = result.toConversationText();
    expect(text, contains('工具：五运六气推算'));
    expect(text, contains('执行状态：SUCCEEDED'));
    expect(text, contains('执行参数：date=2026-11-06'));
    expect(text, contains('推算日期：2026-11-06'));
    expect(text, contains('岁运病候：MISSING'));
    expect(text, contains('来源标识：MISSING'));
    expect(text, contains('说明：仅供理论学习。'));
    expect(result.validateFor('yunqi'), isEmpty);
    expect(result.validateFor('ziwei'), isNotEmpty);
  });
  test('工具结果参数必须与实际执行参数一致', () {
    const matching = AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: {'推算日期': '2026-11-07'},
      arguments: {'date': '2026-11-07'},
    );
    expect(
      matching.validateArgumentsMatch(const {'date': '2026-11-07'}),
      isEmpty,
    );
    expect(
      matching.validateArgumentsMatch(const {'date': '2026-11-06'}),
      isNotEmpty,
    );
    expect(
      matching.validateArgumentsMatch(const {
        'date': '2026-11-07',
        'timezone': 'Asia/Shanghai',
      }),
      isNotEmpty,
    );

    const legacy = AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: {'结果': '旧页面返回'},
    );
    expect(legacy.validateArgumentsMatch(const {'date': '2026-11-07'}), isEmpty);
    expect(
      legacy.withArguments(const {'date': '2026-11-07'}).arguments,
      const {'date': '2026-11-07'},
    );
  });

  test('typed tool result carries source identifiers into the conversation', () {
    const result = AssistantToolResult(
      toolId: 'ziwei',
      title: '紫微斗数排盘',
      values: {'命宫': '寅宫'},
      sourceIds: ['ziwei-engine:local-rules:v1'],
    );
    expect(result.validateFor('ziwei'), isEmpty);
    expect(result.toConversationText(), contains('来源标识：ziwei-engine:local-rules:v1'));
  });

  test('显式取消与无返回值必须使用不同的终态', () {
    const cancelled = AssistantToolResult(
      toolId: 'ziwei',
      title: '紫微斗数排盘',
      status: AssistantToolExecutionStatus.cancelled,
      values: const {},
    );
    expect(cancelled.statusLabel, 'CANCELLED');
    expect(cancelled.toConversationText(), contains('执行状态：CANCELLED'));
    expect(cancelled.validateFor('ziwei'), isEmpty);
  });

  test('无返回值的工具调用必须标记 NO_RESULT 而不是成功', () {
    const result = AssistantToolResult(
      toolId: 'ziwei',
      title: '紫微斗数排盘',
      status: AssistantToolExecutionStatus.noResult,
      values: {'返回内容': 'MISSING'},
      disclaimer: '无法区分取消与旧页面未回传。',
    );
    expect(result.validateFor('ziwei'), isEmpty);
    expect(result.toConversationText(), contains('执行状态：NO_RESULT'));
  });

}
