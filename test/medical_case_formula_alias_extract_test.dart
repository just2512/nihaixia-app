import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
  });

  test('已登记的唯一方名异写归一到方剂正名', () {
    expect(extractFormulaNames('桂枝新加汤'), ['新加汤']);
    expect(extractFormulaNames('耆芍桂酒汤'), ['黄芪芍药桂枝苦酒汤']);
  });

  test('方名正名和箭头分段检索保持原行为', () {
    expect(extractFormulaNames('桂枝汤'), contains('桂枝汤'));
    expect(
      extractFormulaNames('小柴胡汤 → 大柴胡汤'),
      containsAll(['小柴胡汤', '大柴胡汤']),
    );
  });

  test('过滤称号，并跳过映射到多个正名的歧义别名', () {
    expect(extractFormulaNames('虫剂'), isEmpty);
    expect(extractFormulaNames('肾着汤'), isEmpty);
    expect(extractFormulaNames('救逆汤'), isEmpty);
  });

  test('别名与正名在多段出现时按正名归一并去重', () {
    expect(
      extractFormulaNames('耆芍桂酒汤 → 黄芪芍药桂枝苦酒汤'),
      ['黄芪芍药桂枝苦酒汤'],
    );
  });
}
