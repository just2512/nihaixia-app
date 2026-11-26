import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_evidence.dart';
import 'package:nihaisha_app/services/local_structured_evidence_pipeline.dart';

void main() {
  const legacyText = '''以下内容来自 App 内置知识库。
不得补造资料未记载的事实。
[App方剂库 assets/data/formulas.json · guizhi_tang]
来源标识：formula:guizhi_tang
知识库条目定位：assets/data/formulas.json#id=guizhi_tang
方名：桂枝汤
组成药名：桂枝、芍药
[App本草库 assets/data/herbs.json · 桂枝]
来源标识：herb:桂枝
知识库条目定位：assets/data/herbs.json#name=桂枝
药名：桂枝
功用字段：MISSING
[App针灸处方库 assets/data/acupuncture.json · insomnia/entry:7]
来源标识：acupuncture:insomnia:7
知识库条目定位：assets/data/acupuncture.json#category=insomnia&id=7
主诉/病症：失眠
穴位与操作：神门
[App穴位库 assets/data/acupoints.json · 足三里]
来源标识：acupoint:足三里
知识库条目定位：assets/data/acupoints.json#name=足三里
穴名：足三里
定位：犊鼻下三寸
[App内经结构化条目 lib/data/neijing_entries.dart · neijing-001]
来源标识：neijing:neijing-001
知识库条目定位：lib/data/neijing_entries.dart#id=neijing-001
维度：脏腑；标题：十二官相使
原文摘录：心者君主之官''';

  test('adapts all existing local source blocks into typed candidates in text order', () {
    final extracted = LocalStructuredEvidencePipeline.extract(
      requestId: 'local-request-1',
      originalQuery: '查桂枝汤并了解穴位',
      legacyContextText: legacyText,
    );

    expect(extracted.batch.status, CandidateEvidenceBatchStatus.retrieved);
    expect(extracted.batch.derivedQueries.single.queryId, 'legacy-local-q1');
    expect(
      extracted.batch.candidates.map((item) => item.sourceId),
      [
        'formula:guizhi_tang',
        'herb:桂枝',
        'acupuncture:insomnia:7',
        'acupoint:足三里',
        'neijing:neijing-001',
      ],
    );
    expect(
      extracted.batch.candidates.map((item) => item.retrievalMethod),
      [
        'LOCAL_FORMULA_LEGACY_MATCH',
        'LOCAL_HERB_LEGACY_MATCH',
        'LOCAL_ACUPUNCTURE_LEGACY_MATCH',
        'LOCAL_ACUPOINT_LEGACY_MATCH',
        'LOCAL_NEIJING_LEGACY_MATCH',
      ],
    );
    expect(
      extracted.batch.candidates.map((item) => item.title),
      ['桂枝汤', '桂枝', '失眠', '足三里', '十二官相使'],
    );
    expect(extracted.batch.candidates.first.hasLocalBacklink, isTrue);
    expect(extracted.batch.candidates[1].excerpt, contains('功用字段：MISSING'));
    expect(extracted.batch.candidates.last.completeness,
        CandidateEvidenceCompleteness.unknown);

    for (final block in extracted.blocks) {
      expect(
        legacyText.substring(block.startOffset, block.endOffset),
        block.candidate.excerpt,
      );
    }
    expect(extracted.batch.diagnostics, contains('LEGACY_STRUCTURED_TEXT_AND_ORDER_PRESERVED'));
  });

  test('skips malformed or incomplete source blocks rather than inventing IDs or titles', () {
    const malformed = '''[App方剂库 assets/data/formulas.json · unknown]
知识库条目定位：assets/data/formulas.json#id=unknown
方名：未知方
[App本草库 assets/data/herbs.json · unknown]
来源标识：herb:未知药''';

    final extracted = LocalStructuredEvidencePipeline.extract(
      requestId: 'local-request-2',
      originalQuery: '未知药',
      legacyContextText: malformed,
    );

    expect(extracted.batch.candidates, isEmpty);
    expect(extracted.batch.status, CandidateEvidenceBatchStatus.missing);
    expect(extracted.batch.diagnostics, contains('LEGACY_STRUCTURED_BLOCKS_SKIPPED:2'));
  });

  test('rejects empty request identity and empty original query', () {
    expect(
      () => LocalStructuredEvidencePipeline.extract(
        requestId: '',
        originalQuery: '桂枝汤',
        legacyContextText: legacyText,
      ),
      throwsArgumentError,
    );
    expect(
      () => LocalStructuredEvidencePipeline.extract(
        requestId: 'request',
        originalQuery: ' ',
        legacyContextText: legacyText,
      ),
      throwsArgumentError,
    );
  });
}
