import 'package:flutter_test/flutter_test.dart';
import 'package:nihaixia_app/models/assistant_tool_result.dart';

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
    );

    final text = result.toConversationText();
    expect(text, contains('工具：五运六气推算'));
    expect(text, contains('推算日期：2026-11-06'));
    expect(text, contains('岁运病候：MISSING'));
    expect(text, contains('说明：仅供理论学习。'));
  });
}
