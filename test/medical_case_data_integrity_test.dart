import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('医案解析跳过全空模板行，保留全部1256条实质病例记录及原始序号', () async {
    final markdown = await rootBundle.loadString(
      'assets/medical_cases/cases_table.md',
    );
    final cases = parseMedicalCaseTable(markdown);

    expect(cases, hasLength(1256));
    expect(cases.first.seq, 2);
    expect(cases.last.seq, 1257);
    expect(cases.map((item) => item.seq).toSet(), hasLength(1256));
    expect(cases.any((item) => item.seq == 1), isFalse);
    expect(
      cases.every((item) => [
        item.date,
        item.patient,
        item.diagnosis,
        item.mechanism,
        item.western,
        item.formula,
        item.acupuncture,
        item.method,
        item.result,
        item.advice,
        item.view,
      ].any((value) => value.trim().isNotEmpty)),
      isTrue,
    );
    expect(cases.any((item) => item.formula.trim().isEmpty), isTrue);
    expect(cases.any((item) => item.formula.contains('未公开')), isTrue);
  });
}
