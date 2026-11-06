import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupunctureRepository.load();
    await AcupointRepository.load();
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

  test('穴位查询返回定位和操作字段并保留数据来源', () {
    final context = AssistantKnowledgeContextBuilder.build('足三里穴位定位');
    expect(context, contains('App穴位库 assets/data/acupoints.json'));
    expect(context, contains('穴名：足三里'));
  });

  test('针灸主诉查询返回针灸库的穴位处方记录', () {
    final context = AssistantKnowledgeContextBuilder.build('失眠的针灸治疗');
    expect(context, contains('App针灸处方库 assets/data/acupuncture.json'));
  });

  test('内经条目查询区分原文、出处和倪师解读', () {
    final context = AssistantKnowledgeContextBuilder.build('十二官相使');
    expect(context, contains('App内经结构化条目'));
    expect(context, contains('原文摘录：'));
    expect(context, contains('条目所载出处：'));
    expect(context, contains('倪师解读：'));
  });


  test('异步检索可访问古籍原文库并保留书目来源', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('灵枢');
    expect(context, contains('App古籍库'));
    expect(context, contains('App古籍库 · 黄帝内经·灵枢'));
    expect(context, contains('assets/guji/lingshu.txt'));
  });

  test('问诊检索可调用经典全文索引但排除未核验医案库', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync(
      '葛根加半夏汤',
      includeMedicalCases: false,
    );
    expect(context, contains('App经典全文索引'));
    expect(context, isNot(contains('[App医案库')));
  });

  test('异步检索医案时标注内部序号与原始出处缺失', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(context, contains('App医案库'));
    expect(context, contains('内部序号'));
    expect(context, contains('来源定位：MISSING'));
  });

  test('异步检索伤寒金匮全文索引时明确区分倪师讲稿与仲景原文', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('葛根加半夏汤');
    expect(context, contains('App经典全文索引'));
    expect(context, contains('伤寒论讲稿'));
    expect(context, contains('倪师讲稿/整理讲义'));
    expect(context, contains('版本/底本/卷页：MISSING'));
    expect(context, contains('来源标识：shanghan:assets/'));
    expect(context, contains('本地回链：assets/'));
    expect(context, contains('来源定位状态：MISSING'));
    expect(context, contains('不得当作仲景原文'));
  });
  test('本地医案检索注入助手上下文时保留来源缺失边界', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(context, contains('App医案库 assets/medical_cases/cases_table.md'));
    expect(context, contains('来源定位：MISSING'));
    expect(context, contains('核验状态：MISSING'));
    expect(context, contains('版本/底本：MISSING'));
    expect(context, contains('页码：MISSING'));
    expect(context, contains('原文片段：MISSING'));
    expect(context, contains('适用条件：MISSING'));
    expect(context, contains('缺失字段：'));
    expect(context, contains('不代表已核验病例原文或疗效证据'));
  });

}
