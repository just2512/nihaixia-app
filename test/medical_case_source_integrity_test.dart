import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('医案表有效记录数与序号必须一致，排除模板占位行', () async {
    final markdown = await rootBundle.loadString(
      'assets/medical_cases/cases_table.md',
    );
    final cases = parseMedicalCaseTable(markdown);

    // 序号 1 是全空模板行，不是病例；其余编号 2..1257 应全部保留。
    expect(cases, hasLength(1256));
    expect(cases.first.seq, 2);
    expect(cases.last.seq, 1257);
    expect(cases.map((item) => item.seq).toSet(), hasLength(cases.length));
    expect(cases.any((item) => item.seq == 1), isFalse);
  });
}
