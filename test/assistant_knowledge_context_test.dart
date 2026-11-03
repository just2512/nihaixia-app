import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
  });

  test('精确药名查询返回带来源的本草条目', () {
    final context = AssistantKnowledgeContextBuilder.build('柴胡的传统功用是什么？');
    expect(context, contains('App本草库 assets/data/herbs.json'));
    expect(context, contains('药名：柴胡'));
  });

  test('方剂查询返回方剂库原始字段但不注入剂量', () {
    final context = AssistantKnowledgeContextBuilder.build('桂枝汤的组成和适用条文是什么？');
    expect(context, contains('App方剂库 assets/data/formulas.json'));
    expect(context, contains('方名：桂枝汤'));
    expect(context, isNot(contains('克')));
  });

  test('无命中时返回空上下文，避免把无关数据塞进模型', () {
    expect(AssistantKnowledgeContextBuilder.build('今天的天气怎么样'), isEmpty);
  });

  test('上下文长度有硬上限', () {
    final context = AssistantKnowledgeContextBuilder.build('柴胡 桂枝汤');
    expect(
      context.length,
      lessThanOrEqualTo(AssistantKnowledgeContextBuilder.maxContextCharacters),
    );
  });
}
