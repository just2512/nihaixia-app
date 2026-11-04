import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('医案解析保留全部1257条原始数字序号记录，包括方剂缺失病例', () async {
    final markdown = await rootBundle.loadString(
      'assets/medical_cases/cases_table.md',
    );
    final cases = parseMedicalCaseTable(markdown);

    expect(cases, hasLength(1257));
    expect(cases.first.seq, 1);
    expect(cases.last.seq, 1257);
    expect(cases.map((item) => item.seq).toSet(), hasLength(1257));
    expect(cases.any((item) => item.formula.trim().isEmpty), isTrue);
    expect(cases.any((item) => item.formula.contains('未公开')), isTrue);
  });
}
