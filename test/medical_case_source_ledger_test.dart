import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/medical_case_source_ledger.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';

void main() {
  test('未提供原始出处时所有定位字段明确为 MISSING', () {
    const ledger = MedicalCaseSourceLedger.missing;
    expect(ledger.status, 'MISSING');
    expect(ledger.toDisplayText().split('\n'), hasLength(greaterThan(5)));
    expect(ledger.hasCompleteLocator, isFalse);
    expect(ledger.isVerified, isFalse);
    expect(ledger.missingFields, containsAll([
      '原始书名/病例来源',
      '版本/底本',
      '卷次',
      '页码',
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
    expect(ledger.isVerified, isFalse);
    expect(ledger.valueOf('page'), 'MISSING');
  });

  test('完整定位字段和显式核验状态才允许 VERIFIED', () {
    const ledger = MedicalCaseSourceLedger(
      sourceTitle: '伤寒论',
      edition: '宋本',
      volume: '卷三',
      page: '影印本第 42 页',
      passage: '辨太阳病脉证并治上第五',
      variant: 'MISSING',
      verificationStatus: 'VERIFIED',
    );
    expect(ledger.status, 'VERIFIED');
    expect(ledger.hasCompleteLocator, isTrue);
    expect(ledger.isVerified, isTrue);
  });

  test('来源账本 JSON 往返保留定位字段和核验状态', () {
    const original = MedicalCaseSourceLedger(
      sourceTitle: '金匮要略',
      edition: 'MISSING',
      volume: 'MISSING',
      page: 'MISSING',
      passage: '痰饮咳嗽病脉证并治',
      verificationStatus: 'PENDING',
    );
    final restored = MedicalCaseSourceLedger.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expect(restored.status, 'PENDING');
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
      verificationStatus: 'VERIFIED',
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

}
