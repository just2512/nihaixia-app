import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/dream_tool_executor.dart';

void main() {
  test('单一具体情节只返回对应原始词条和来源', () async {
    final result = await DreamToolExecutor.execute({
      'dream_text': '我昨晚梦见一条蛇缠身，帮我解梦',
    });

    expect(result.statusLabel, 'SUCCEEDED');
    expect(result.values['检索状态'], 'SINGLE_MATCH');
    expect(result.values['词条ID'], 'animal_037');
    expect(result.values['梦境词条'], '梦见蛇缠身');
    expect(result.values['原始吉凶标签（民俗文本）'], '凶');
    expect(result.sourceIds, [DreamToolExecutor.sourceId]);
    expect(result.arguments, {
      'dream_text': '我昨晚梦见一条蛇缠身，帮我解梦',
    });
    expect(result.disclaimer, contains('不是事实判断'));
  });

  test('重复关键词蛇返回候选，不擅自选择第一条', () async {
    final result = await DreamToolExecutor.execute({
      'dream_text': '昨晚梦见蛇',
    });

    expect(result.statusLabel, 'SUCCEEDED');
    expect(result.values['检索状态'], 'CANDIDATES_REQUIRE_CLARIFICATION');
    expect(result.values['候选总数'], '4');
    final candidates = result.values['候选列表（按数据集原始顺序，不代表相关度）']!;
    expect(candidates, contains('animal_035'));
    expect(candidates, contains('animal_036'));
    expect(candidates, contains('animal_037'));
    expect(candidates, contains('animal_038'));
    expect(result.values.containsKey('词条ID'), isFalse);
    expect(result.values['澄清要求'], contains('不得替用户选择'));
  });

  test('没有本地匹配时返回 NO_RESULT，不生成解释内容', () async {
    final result = await DreamToolExecutor.execute({
      'dream_text': '昨晚梦见一个无法识别的抽象场景',
    });

    expect(result.statusLabel, 'NO_RESULT');
    expect(result.values['检索状态'], 'NO_MATCH');
    expect(result.values.containsKey('词条释义原文'), isFalse);
  });

  test('拒绝未声明参数，不带入模型推断字段', () async {
    final result = await DreamToolExecutor.execute({
      'dream_text': '梦见蛇',
      'auspicious': '大吉',
    });

    expect(result.statusLabel, 'FAILED');
    expect(result.values['未执行原因'], contains('未声明'));
    expect(result.arguments, contains('auspicious'));
  });
}
