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

  test('精确方剂查询不扩展到仅共享药味的其他方剂', () {
    final context = AssistantKnowledgeContextBuilder.build('桂枝汤的组成和适用条文是什么？');
    expect(context, contains('方名：桂枝汤'));
    expect(context, isNot(contains('方名：麻黄汤')));
  });

  test('单味药查询仍按方剂组成匹配相关方剂', () {
    // 白蜜在当前方剂库中只属于大半夏汤，避免断言被 maxFormulaEntries
    // 截断的高频药味查询必须返回任意指定的前几首方剂。
    final context = AssistantKnowledgeContextBuilder.build('白蜜');
    expect(context, contains('方名：大半夏汤'));
  });

  test('学习助手可检索并引用本草讲稿的本地来源', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '丹砂',
      includeMedicalCases: false,
    );
    final source = result.sources.where(
      (item) =>
          item.sourceKind == 'lecture' &&
          item.sourceId.startsWith('bencao:assets/bencao_lecture/'),
    );
    expect(source, isNotEmpty);
    expect(source.first.localBacklink, startsWith('assets/bencao_lecture/'));
    expect(source.first.localBacklink, isNot('MISSING'));
  });

  test('无命中时返回空上下文，避免把无关数据塞进模型', () {
    expect(AssistantKnowledgeContextBuilder.build('今天的天气怎么样'), isEmpty);
  });

  test('确定性检索门禁只对中医信号或本地知识实体开启', () {
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('桂枝汤的组成有哪些？'),
      isTrue,
    );
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('经方度量衡换算'),
      isTrue,
    );
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('子午流注开穴结果'),
      isTrue,
    );
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('纳子法与纳甲法'),
      isTrue,
    );
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('谢谢'),
      isFalse,
    );
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('正官是什么'),
      isFalse,
    );
    expect(
      AssistantKnowledgeContextBuilder.shouldRetrieveForQuery('今天的天气怎么样'),
      isFalse,
    );
  });


  test('检索状态具有稳定的大写契约标签', () {
    const expected = {
      AssistantKnowledgeRetrievalStatus.noResults: 'NO_RESULTS',
      AssistantKnowledgeRetrievalStatus.retrieved: 'RETRIEVED',
      AssistantKnowledgeRetrievalStatus.partial: 'PARTIAL',
      AssistantKnowledgeRetrievalStatus.failed: 'FAILED',
    };
    for (final entry in expected.entries) {
      expect(
        AssistantKnowledgeContextResult(
          text: '',
          status: entry.key,
        ).statusLabel,
        entry.value,
      );
    }
  });

  test('异步检索明确区分无命中与成功命中', () async {
    final empty = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync('今天的天气怎么样');
    expect(empty.status, AssistantKnowledgeRetrievalStatus.noResults);
    expect(empty.sources, isEmpty);

    final found = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync('柴胡');
    expect(
      found.status,
      isNot(AssistantKnowledgeRetrievalStatus.noResults),
    );
    expect(found.status, isNot(AssistantKnowledgeRetrievalStatus.failed));
    expect(found.sources, isNotEmpty);
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

  test('问诊检索可引用医案库本地条目并保留来源回链', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '医案 桂枝汤',
      includeMedicalCases: true,
    );
    final caseSources = result.sources
        .where((source) => source.sourceKind == 'medical_case')
        .toList(growable: false);

    expect(caseSources, isNotEmpty);
    expect(result.text, contains('[App医案库'));
    expect(result.citationFooter, contains('资料类型：App 医案库整理条目'));
    expect(result.citationFooter, contains('知识库条目定位：medical_case:internal-seq:'));
    expect(result.citationFooter, contains('来源标识：medical_case:'));
    expect(result.citationFooter, isNot(contains('MISSING')));
    for (final source in caseSources) {
      expect(source.sourceId, startsWith('medical_case:'));
      expect(source.localBacklink, startsWith('medical_case:internal-seq:'));
    }
  });

  test('古籍章节来源标识可反查到精确内部章节且不提升纸本核验状态', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '灵枢 经脉',
      includeMedicalCases: false,
    );
    final gujiSources = result.sources
        .where((source) => source.sourceId.startsWith('guji:'))
        .toList(growable: false);

    expect(gujiSources, isNotEmpty);
    expect(result.rankedEvidenceIds, isNotEmpty);
    expect(result.knownEvidenceIds.toSet(),
        containsAll(result.rankedEvidenceIds));
    expect(result.sourceIdByEvidenceId.keys.toSet(),
        equals(result.rankedEvidenceIds.toSet()));
    expect(result.rankedEvidence.every((item) =>
        item.sourceId.isNotEmpty && result.text.contains('来源标识：${item.sourceId}')),
        isTrue);
    expect(result.evidenceIndexContext, contains('evidenceId='));

    expect(result.text, contains('来源标识：guji:lingshu:'));
    expect(result.text, contains('纸本版本/卷页核验状态：UNKNOWN'));
    for (final source in gujiSources) {
      expect(source.sourceLabel, '黄帝内经·灵枢');
      expect(source.localBacklink, startsWith('guji:lingshu#chapter:'));
      expect(source.locatorStatus, 'PARTIAL');
      expect(source.sourceKind, 'classic_text');
      expect(source.sourceVerificationStatus, 'UNKNOWN');
      expect(source.bibliographicLocatorVerified, isFalse);
    }
    expect(result.citationFooter, contains('黄帝内经·灵枢'));
    expect(result.citationFooter, contains('来源标识：guji:lingshu:'));
  });

  test('异步检索医案时提供可回查的知识库条目定位', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(context, contains('App医案库'));
    expect(context, contains('知识库条目定位：medical_case:internal-seq:'));
    expect(context, contains('来源标识：medical_case:'));
    expect(context, isNot(contains('纸本定位核验状态')));
    expect(context, isNot(contains('来源定位：MISSING')));
  });

  test('异步检索将课程讲稿作为本地知识库资料定位', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('葛根加半夏汤');
    expect(context, contains('App经典全文索引'));
    expect(context, contains('伤寒论讲稿'));
    expect(context, contains('资料类型：倪师讲稿/整理讲义（学习资料）'));
    expect(context, contains('来源标识：shanghan:assets/'));
    expect(context, contains('知识库条目定位：assets/shanghan/'));
    expect(context, contains('资料类型说明：当前引用对象为 App 内课程讲稿/整理讲义知识条目。'));
    expect(context, isNot(contains('版本/底本/卷页：MISSING')));
    expect(context, isNot(contains('纸本版本/卷页')));
  });

  test('讲稿引用尾注显示本地学习资料回链而不把纸本卷页当作必填', () async {
    final result =
        await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '葛根加半夏汤',
      includeMedicalCases: false,
    );
    expect(result.status, AssistantKnowledgeRetrievalStatus.retrieved);
    expect(result.text, contains('来源标识：shanghan:assets/'));
    expect(result.sources, isNotEmpty);
    expect(result.sourceIds, isNotEmpty);
    expect(result.sourceIds.every((id) => id.isNotEmpty), isTrue);
    expect(result.citationFooter, contains('资料类型：课程讲稿/整理讲义（学习资料）'));
    expect(result.citationFooter, contains('知识库条目定位：assets/shanghan/'));
    expect(result.citationFooter, contains('来源标识：shanghan:assets/'));
    expect(result.citationFooter, isNot(contains('纸本版本/卷页')));
    expect(result.citationFooter, isNot(contains('MISSING')));
    expect(result.sources.every((source) => source.locatorStatus != 'VERIFIED'), isTrue);
  });

  test('知识引用尾注使用真实换行而不是字面量转义', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '葛根加半夏汤',
      includeMedicalCases: false,
    );
    expect(result.citationFooter, contains('\n  资料类型：'));
    expect(result.citationFooter, isNot(contains(r'\n  来源类型：')));
  });

  test('App 古籍文本引用指向具体知识库章节', () {
    const source = AssistantKnowledgeSourceReference(
      sourceId: 'guji:shanghan_lun:1',
      sourceLabel: '伤寒论',
      title: '卷一',
      localBacklink: 'guji:shanghan_lun#chapter:1',
      locatorStatus: 'MISSING',
      sourceKind: 'classic_text',
      sourceVerificationStatus: 'UNKNOWN',
    );
    final citation = source.toCitationText();
    expect(citation, contains('资料类型：App 古籍文本知识条目'));
    expect(citation, contains('知识库条目定位：guji:shanghan_lun#chapter:1'));
    expect(citation, contains('来源标识：guji:shanghan_lun:1'));
    expect(citation, isNot(contains('MISSING')));
  });

  test('本地医案检索注入助手上下文时保留可定位的知识库条目', () async {
    final context = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(context, contains('[App医案库 · 条目'));
    expect(context, contains('知识库条目定位：medical_case:internal-seq:'));
    expect(context, contains('来源标识：medical_case:'));
    expect(context, contains('资料类型：App 医案库本地整理记录'));
    expect(context, isNot(contains('纸本定位核验状态')));
    expect(context, isNot(contains('来源定位：MISSING')));
    expect(context, isNot(contains('MISSING（原文来源核验状态')));
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

  test('医案引用回链到知识库条目且不输出外部书目缺失', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '医案 肝癌',
    );
    final caseSources = result.sources
        .where((source) => source.sourceKind == 'medical_case')
        .toList(growable: false);
    expect(caseSources, isNotEmpty);
    expect(caseSources.any((source) =>
        source.sourceVerificationStatus == 'VERIFIED'), isTrue);
    expect(
      caseSources.every((source) =>
          source.locatorStatus == 'MISSING' &&
          !source.bibliographicLocatorVerified),
      isTrue,
    );
    expect(result.citationFooter, contains('资料类型：App 医案库整理条目'));
    expect(result.citationFooter, contains('知识库条目定位：medical_case:internal-seq:'));
    expect(result.citationFooter, isNot(contains('书目定位状态')));
    expect(result.citationFooter, isNot(contains('MISSING')));
  });

  test('医案来源标识可反查知识库条目并进入结构化引用', () async {
    final result = await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
      '桂枝汤',
    );
    expect(result.text, contains('来源标识：medical_case:'));
    expect(result.text, contains('知识库条目定位：medical_case:internal-seq:'));

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
    expect(result.citationFooter, contains('资料类型：App 医案库整理条目'));
    expect(result.citationFooter, contains('知识库条目定位：medical_case:internal-seq:'));
    expect(result.citationFooter, contains('来源标识：medical_case:'));
    expect(result.citationFooter, isNot(contains('书目定位状态')));
    expect(result.citationFooter, isNot(contains('MISSING')));
  });



  test('经典命中区分本地知识库回链与外部书目元数据', () {
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


  test('经典检索将本地讲稿标记为学习资料并提供知识库定位', () async {
    final lecture = await AssistantKnowledgeContextBuilder.buildAsync('葛根加半夏汤');
    expect(lecture, contains('知识库条目定位：assets/shanghan/'));
    expect(lecture, contains('来源标识：shanghan:assets/shanghan/'));
    expect(lecture, contains('资料类型说明：当前引用对象为 App 内课程讲稿/整理讲义知识条目。'));
    expect(lecture, isNot(contains('版本/底本/卷页：MISSING')));
    expect(lecture, isNot(contains('纸本版本/卷页')));
    expect(lecture, isNot(contains('纸本版本/卷页：VERIFIED')));
    expect(lecture, isNot(contains('已完成校勘')));
  });

  test('医案关联上下文使用稳定知识库条目编号定位而不显示书目缺失', () async {
    final cases = await AssistantKnowledgeContextBuilder.buildAsync('桂枝汤');
    expect(cases, contains('[App医案库 · 条目'));
    expect(cases, contains('知识库条目定位：medical_case:internal-seq:'));
    expect(cases, contains('来源标识：medical_case:'));
    expect(cases, isNot(contains('来源定位：MISSING')));
    expect(cases, isNot(contains('纸本定位核验状态')));
  });

  test('生产检索接入统一多源排序并保留旧呈现顺序与来源限额', () async {
    final guji = await AssistantKnowledgeContextBuilder.buildAsync(
      '灵枢 经脉',
      includeMedicalCases: false,
    );
    final classicIndex = guji.indexOf('[App经典全文索引');
    final gujiIndex = guji.indexOf('[App古籍库');
    expect(gujiIndex, isNonNegative);
    if (classicIndex >= 0) {
      expect(classicIndex, lessThan(gujiIndex));
    }
    expect(RegExp(r'章节：').allMatches(guji).length, lessThanOrEqualTo(2));
    expect(guji, contains('纸本版本/卷页核验状态：UNKNOWN'));

    final medical = await AssistantKnowledgeContextBuilder.buildAsync(
      '医案 桂枝汤',
      includeMedicalCases: true,
    );
    expect(
      RegExp(r'\[App医案库 · 条目').allMatches(medical).length,
      lessThanOrEqualTo(2),
    );
    final classicIndexMedical = medical.indexOf('[App经典全文索引');
    final medicalIndex = medical.indexOf('[App医案库');
    if (classicIndexMedical >= 0 && medicalIndex >= 0) {
      expect(classicIndexMedical, lessThan(medicalIndex));
    }
    expect(
      medical.length,
      lessThanOrEqualTo(AssistantKnowledgeContextBuilder.maxContextCharacters),
    );
  });

}
