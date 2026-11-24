import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/xiaoliuren_data.dart';

void main() {
  group('小六壬规则数据（面向玄学模式 AI 上下文）', () {
    final data = describeXiaoliurenRuleData();

    test('包含数据层确有定义的字段：宫名、六神、歌诀、起课口径', () {
      // 六宫顺序
      expect(data, contains('大安'));
      expect(data, contains('留连'));
      expect(data, contains('速喜'));
      expect(data, contains('赤口'));
      expect(data, contains('小吉'));
      expect(data, contains('空亡'));
      expect(data, contains('六宫固定顺序'));
      // 六神对应（大安=青龙）
      expect(data, contains('青龙'));
      // 歌诀原文保留
      expect(data, contains('求财在坤方'));
      // 起课口径并存
      expect(data, contains('通行掌诀'));
      expect(data, contains('多能鄙事'));
      // 来源标识为 App 内置规则数据，非古籍/文献
      expect(data, contains('local-data:xiaoliuren-rule-data'));
    });

    test('声明五行与一般方位未定义，禁止推导', () {
      expect(data, contains('App 数据未定义各宫的五行属性与一般方位'));
      expect(data, contains('不得推导'));
      expect(data, contains('不得改写为宫位本身的五行或方位属性'));
    });

    test('不把某一术数流派口径伪装成唯一正解（不写死五行/方位）', () {
      expect(data, isNot(contains('大安属木')));
      expect(data, isNot(contains('大安属土')));
      expect(data, isNot(contains('大安方位东方')));
      expect(data, isNot(contains('大安方位西南')));
      expect(data, isNot(contains('留连属水')));
    });
  });
}