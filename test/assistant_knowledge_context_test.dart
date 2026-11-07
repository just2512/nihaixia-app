import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/classic_search_service.dart';

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

  test('异步检索引用只暴露可反查的来源标识，纸本版本仍保持 MISSING', () async {
    final result =
        await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '葛根加半夏汤',
      includeMedicalCases: false,
    );
    expect(result.text, contains('来源标识：shanghan:assets/'));
    expect(result.sources, isNotEmpty);
    expect(result.sourceIds, isNotEmpty);
    expect(result.sourceIds.every((id) => id.isNotEmpty), isTrue);
    expect(result.citationFooter, contains('纸本版本/卷页：MISSING'));
    expect(result.citationFooter, contains('来源标识：'));
    expect(result.sources.every((source) => source.locatorStatus != 'VERIFIED'), isTrue);
  });

  test('本地医案检索注入助手上下文时保留来源缺失边界', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(context, contains('App医案库 assets/medical_cases/cases_table.md'));
    expect(context, contains('来源核验状态：MISSING'));
    expect(context, contains('来源定位：MISSING'));
    expect(context, contains('来源账本：'));
    expect(context, contains('核验状态：MISSING'));
    expect(context, contains('病例内容本身不构成疗效证据'));
  });


  test('方剂、本草、针灸、穴位和内经条目均生成可反查的来源引用', () async {
    const scenarios = [
      ('桂枝汤', 'formula'),
      ('柴胡', 'herb'),
      ('失眠的针灸治疗', 'acupuncture'),
      ('足三里穴位定位', 'acupoint'),
      ('十二官相使', 'neijing'),
    ];

    for (final scenario in scenarios) {
      final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
        scenario.$1,
        includeMedicalCases: false,
      );
      final matches = result.sources
          .where((source) => source.sourceKind == scenario.$2)
          .toList(growable: false);
      expect(
        matches,
        isNotEmpty,
        reason: '${scenario.$1} 应返回 ${scenario.$2} 类型的可反查来源',
      );
      for (final source in matches) {
        expect(source.sourceId, isNotEmpty);
        expect(source.localBacklink, isNotEmpty);
        expect(source.localBacklink, isNot('MISSING'));
        expect(source.bibliographicLocatorVerified, isFalse);
        expect(source.locatorStatus, 'MISSING');
      }
    }
  });

  test('医案来源标识可反查账本记录并进入结构化引用，不把内部序号冒充出处', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '桂枝汤',
    );
    expect(result.text, contains('来源标识：medical_case:'));
    expect(result.text, contains('本地回链：medical_case:internal-seq:'));

    final caseSources = result.sources
        .where((source) => source.sourceKind == 'medical_case')
        .toList(growable: false);
    expect(caseSources, isNotEmpty);
    for (final source in caseSources) {
      expect(source.sourceId, startsWith('medical_case:'));
      expect(source.localBacklink, startsWith('medical_case:internal-seq:'));
      expect(source.locatorStatus, 'MISSING');
      expect(source.bibliographicLocatorVerified, isFalse);
    }
    expect(result.citationFooter, contains('来源类型：medical_case'));
    expect(result.citationFooter, contains('书目定位状态：MISSING'));
  });



  test('经典命中区分可回链与纸本出处核验状态', () {
    const lecture = ClassicHit(
      source: 'shanghan',
      sourceLabel: '伤寒论讲稿',
      title: '葛根加半夏汤',
      asset: 'assets/shanghan/lecture.md',
      snippet: '讲稿摘要',
    );
    expect(lecture.hasLocalBacklink, isTrue);
    expect(lecture.localBacklink, 'assets/shanghan/lecture.md');
    expect(lecture.hasVerifiedBibliographicLocator, isFalse);
    expect(lecture.locatorStatus, 'MISSING');

    const classic = ClassicHit(
      source: 'guji',
      sourceLabel: '灵枢',
      title: '本神',
      bookId: 'lingshu',
      chapterIndex: 5,
      snippet: '原文摘要',
    );
    expect(classic.hasLocalBacklink, isTrue);
    expect(classic.localBacklink, 'guji:lingshu#chapter:5');
    expect(classic.hasVerifiedBibliographicLocator, isFalse);
    expect(classic.locatorStatus, 'PARTIAL');
  });

  test('缺少可定位字段的经典命中不得伪造本地回链', () {
    const missing = ClassicHit(
      source: 'unknown',
      sourceLabel: '未知来源',
      title: 'MISSING',
      snippet: 'MISSING',
    );
    expect(missing.hasLocalBacklink, isFalse);
    expect(missing.localBacklink, 'MISSING');
    expect(missing.hasVerifiedBibliographicLocator, isFalse);
  });


  test('经典检索不得把本地讲稿或未校勘文本伪装成已核验原文', () async {
    final lecture = await AssistantKnowledgeContextBuilder.buildAsync('葛根加半夏汤');
    expect(lecture, contains('资料类型：倪师讲稿/整理讲义'));
    expect(lecture, contains('版本/底本/卷页：MISSING'));
    expect(lecture, contains('不得当作仲景原文'));
    expect(lecture, isNot(contains('已完成校勘')));
  });

  test('医案关联上下文不得把内部序号升级为原始出处', () async {
    final cases = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(cases, contains('内部序号'));
    expect(cases, contains('来源定位：MISSING'));
    expect(cases, contains('内部序号不是原始病例页码或稳定来源 ID'));
    expect(cases, contains('病例内容本身不构成疗效证据'));
  });

  test('结构化来源引用使用真实换行而非反斜杠文本', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '葛根加半夏汤',
      includeMedicalCases: false,
    );
    expect(result.sources, isNotEmpty);
    expect(result.citationFooter, contains('\n  来源类型：'));
    expect(result.citationFooter, isNot(contains(r'\n  来源类型：')));
  });

}
