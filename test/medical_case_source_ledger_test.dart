import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/medical_case_source_ledger.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('未提供原始出处时所有定位字段明确为 MISSING', () {
    const ledger = MedicalCaseSourceLedger.missing;
    expect(ledger.status, 'MISSING');
    expect(ledger.toDisplayText().split('\n'), hasLength(11));
    expect(ledger.hasCompleteLocator, isFalse);
    expect(ledger.isVerified, isFalse);
    expect(ledger.missingFields, containsAll([
      '原始书名/病例来源',
      '纸本版本/底本',
      '纸本卷次',
      '纸本页码',
      '篇章/病例标题',
    ]));
  });

  test('仅有内部来源名称或卷次不能被标记为 VERIFIED', () {
    final ledger = MedicalCaseSourceLedger.fromJson({
      'sourceTitle': '伤寒论',
      'volume': '辨太阳病脉证并治上',
      'verificationStatus': 'VERIFIED',
    });
    expect(ledger.status, 'MISSING');
    expect(ledger.verificationStatus, 'MISSING');
    expect(ledger.isVerified, isFalse);
    expect(ledger.valueOf('page'), 'MISSING');
  });

  test('网页原文核验与纸本版本卷页核验相互独立', () {
    final ledger = MedicalCaseSourceLedger.fromJson({
      'sourceTitle': '网页病例原文',
      'edition': '网页原文（网页版本）',
      'volume': '不适用（网页文章，无卷次）',
      'page': 'https://example.org/case',
      'passage': '病例原文段落',
      'originalExcerpt': '原文摘录',
      'applicability': '对应网页病例原文的具体适用范围。',
      'verificationStatus': 'VERIFIED',
    });
    expect(ledger.isSourceVerified, isTrue);
    expect(ledger.sourceStatus, 'VERIFIED');
    expect(ledger.isVerified, isFalse);
    expect(ledger.status, 'MISSING');
    expect(ledger.missingFields, containsAll([
      '纸本版本/底本',
      '纸本卷次',
      '纸本页码',
    ]));
  });

  test('完整纸本定位字段和显式纸本核验状态才允许 VERIFIED', () {
    const ledger = MedicalCaseSourceLedger(
      sourceTitle: '伤寒论',
      edition: '宋本',
      volume: '卷三',
      page: '影印本第 42 页',
      passage: '辨太阳病脉证并治上第五',
      originalExcerpt: '太阳之为病，脉浮，头项强痛而恶寒。',
      applicability: '历史文本来源核验；不得直接作为个体诊疗建议。',
      variant: 'MISSING',
      verificationStatus: 'VERIFIED',
      bibliographicLocatorStatus: 'VERIFIED',
    );
    expect(ledger.status, 'VERIFIED');
    expect(ledger.hasCompleteLocator, isTrue);
    expect(ledger.isVerified, isTrue);
  });

  test('来源账本 JSON 往返保留完整来源的待核状态', () {
    const original = MedicalCaseSourceLedger(
      sourceTitle: '金匮要略',
      edition: '宋本影印本',
      volume: '卷三',
      page: '第42页',
      passage: '痰饮咳嗽病脉证并治',
      originalExcerpt: '原文待进一步校勘的完整摘录占位文本。',
      applicability: '对应痰饮咳嗽病脉证并治篇的具体条文。',
      variant: '异文待核',
      verificationStatus: 'PENDING',
      bibliographicLocatorStatus: 'PENDING',
    );
    final restored = MedicalCaseSourceLedger.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expect(restored.sourceStatus, 'PENDING');
    expect(restored.status, 'PENDING');
  });

  test('来源字段或适用条件缺失时，PENDING 不得掩盖 MISSING', () {
    const incomplete = MedicalCaseSourceLedger(
      sourceTitle: '金匮要略',
      verificationStatus: 'PENDING',
      bibliographicLocatorStatus: 'PENDING',
    );
    expect(incomplete.sourceStatus, 'MISSING');
    expect(incomplete.status, 'MISSING');

    final raw = <String, dynamic>{
      'sourceTitle': '金匮要略',
      'edition': 'MISSING',
      'volume': 'MISSING',
      'page': 'MISSING',
      'passage': '痰饮咳嗽病脉证并治',
      'originalExcerpt': 'MISSING',
      'applicability': 'MISSING',
      'verificationStatus': 'PENDING',
      'bibliographicLocatorStatus': 'PENDING',
    };
    final restored = MedicalCaseSourceLedger.fromJson(raw);
    expect(restored.sourceStatus, 'MISSING');
    expect(restored.status, 'MISSING');
    expect(restored.toDisplayText(), contains('适用条件：MISSING'));
  });
  test('医案解析按内部主键关联账本，未匹配记录仍保持 MISSING', () {
    const md = '''
| 序号 | 日期 | 患者 | 诊断 | 病机 | 西医背景 | 方剂 | 针灸 | 治法 | 结果 | 医嘱 | 观点 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 42 | 1988 | 女 | 太阳病 | 表证 | --- | 桂枝汤 | --- | 解表 | 好转 | --- | 记录 |
| 43 | 1989 | 男 | 少阳病 | 枢机不利 | --- | --- | --- | 和解 | --- | --- | --- |
''';
    const verified = MedicalCaseSourceLedger(
      sourceTitle: '伤寒论',
      edition: '宋本',
      volume: '卷三',
      page: '第 42 页',
      passage: '辨太阳病脉证并治上',
      originalExcerpt: '太阳之为病，脉浮，头项强痛而恶寒。',
      applicability: '用于病例来源定位核验，不作为个体诊疗建议。',
      verificationStatus: 'VERIFIED',
      bibliographicLocatorStatus: 'VERIFIED',
    );
    final cases = parseMedicalCaseTable(
      md,
      sourceLedgers: const {42: verified},
    );
    expect(cases, hasLength(2));
    expect(cases.first.sourceLedger.status, 'VERIFIED');
    expect(cases.last.sourceLedger.status, 'MISSING');
    expect(cases.last.toShareText(), contains('原始来源账本'));
  });

  test('来源账本覆盖医案资产中的每一条有效记录', () async {
    final table = await rootBundle.loadString(
      'assets/medical_cases/cases_table.md',
    );
    final ledgerText = await rootBundle.loadString(
      'assets/medical_cases/source_ledger.json',
    );
    final decoded = jsonDecode(ledgerText) as Map<String, dynamic>;
    final records = decoded['records'] as Map<String, dynamic>;
    final cases = parseMedicalCaseTable(table);
    expect(cases, isNotEmpty);
    expect(
      cases.every((medicalCase) => records.containsKey(medicalCase.seq.toString())),
      isTrue,
    );
    expect(
      records.keys.toSet(),
      cases.map((medicalCase) => medicalCase.seq.toString()).toSet(),
      reason: '来源账本不能残留已从医案表删除的孤立主键',
    );
    final ledgers = {
      for (final entry in records.entries)
        int.parse(entry.key): MedicalCaseSourceLedger.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    };
    final linked = parseMedicalCaseTable(table, sourceLedgers: ledgers);
    expect(linked, hasLength(cases.length));
    final sourceVerifiedSequences = linked
        .where((medicalCase) => medicalCase.sourceLedger.isSourceVerified)
        .map((medicalCase) => medicalCase.seq)
        .toSet();
    expect(sourceVerifiedSequences, {2, 3, 4, 5, 6, 7, 8, 9, 10, 92});
    expect(
      linked.where((medicalCase) => medicalCase.sourceLedger.isVerified),
      isEmpty,
      reason: '网页原文核验不能冒充纸本版本、卷次和页码已核验',
    );
    expect(
      linked.every((medicalCase) => medicalCase.sourceLedger.status == 'MISSING'),
      isTrue,
      reason: '当前账本尚无任何记录完成纸本/影印本版本、卷次和页码核验',
    );
    expect(
      records.values.every((raw) {
        final record = raw as Map<String, dynamic>;
        final sourceStatus = record['verificationStatus'];
        final restored = MedicalCaseSourceLedger.fromJson(record);
        return (sourceStatus == 'MISSING' ||
                sourceStatus == 'PENDING' ||
                sourceStatus == 'VERIFIED') &&
            restored.sourceStatus == sourceStatus &&
            restored.bibliographicLocatorStatus == 'MISSING' &&
            !restored.isVerified;
      }),
      isTrue,
    );
  });


  test('空白字符串不能冒充完整来源定位字段', () {
    const ledger = MedicalCaseSourceLedger(
      sourceTitle: '伤寒论',
      edition: '宋本',
      volume: '卷三',
      page: '   ',
      passage: '辨太阳病脉证并治上',
      originalExcerpt: '太阳之为病，脉浮，头项强痛而恶寒。',
      verificationStatus: 'VERIFIED',
    );
    expect(ledger.hasCompleteLocator, isFalse);
    expect(ledger.isVerified, isFalse);
    expect(ledger.status, 'MISSING');
    expect(ledger.missingFields, contains('纸本页码'));
  });

}
