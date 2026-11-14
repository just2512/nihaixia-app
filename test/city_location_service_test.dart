import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/city_location_service.dart';

const _sampleJson = '''
[
  {"name":"北京市","lng":116.407526,"lat":39.904030,"province":"北京市"},
  {"name":"上海市","lng":121.473701,"lat":31.230416,"province":"上海市"},
  {"name":"广州市","lng":113.264385,"lat":23.129112,"province":"广东省"},
  {"name":"杭州市","lng":120.155070,"lat":30.274085,"province":"浙江省"},
  {"name":"宁波市","lng":121.550000,"lat":29.870000,"province":"浙江省"}
]
''';

void main() {
  group('CityLocationService.parseJson', () {
    test('解析字段正确（name/province/lng/lat）', () {
      final list = CityLocationService.parseJson(_sampleJson);
      expect(list.length, 5);
      final bj = list.first;
      expect(bj.name, '北京市');
      expect(bj.province, '北京市');
      expect(bj.lng, closeTo(116.407526, 1e-6));
      expect(bj.lat, closeTo(39.904030, 1e-6));
      expect(bj.displayName, '北京市（北京市）');
    });

    test('province 为空时 displayName 不含括号', () {
      const json = '[{"name":"示例市","lng":100.0,"lat":20.0,"province":""}]';
      final c = CityLocationService.parseJson(json).first;
      expect(c.displayName, '示例市');
    });
  });

  group('CityLocationService.searchIn', () {
    final all = CityLocationService.parseJson(_sampleJson);

    test('空查询返回前 limit 条', () {
      final r = CityLocationService.searchIn(all, '', 3);
      expect(r.length, 3);
      expect(r.first.name, '北京市');
    });

    test('按城市名模糊匹配', () {
      final r = CityLocationService.searchIn(all, '州');
      expect(r.map((c) => c.name), containsAll(['广州市', '杭州市']));
      expect(r.map((c) => c.name), isNot(contains('北京市')));
      expect(r.map((c) => c.name), isNot(contains('宁波市')));
    });

    test('按省份匹配（浙江→杭州、宁波）', () {
      final r = CityLocationService.searchIn(all, '浙江');
      expect(r.map((c) => c.name), containsAll(['杭州市', '宁波市']));
      expect(r.map((c) => c.name), isNot(contains('上海市')));
    });

    test('无匹配返回空', () {
      final r = CityLocationService.searchIn(all, '乌鲁木齐');
      expect(r, isEmpty);
    });

    test('大小写/空格不影响（trim 后为空走浏览）', () {
      final r = CityLocationService.searchIn(all, '   ');
      expect(r.length, 5);
    });
  });
  group('CityLocationService.findUniqueIn', () {
    final sample = CityLocationService.parseJson('''
[
  {"name":"上海市","lng":121.47,"lat":31.23,"province":"上海市"},
  {"name":"长宁区","lng":121.42,"lat":31.22,"province":"上海市","city":"上海市"},
  {"name":"长宁区","lng":111.62,"lat":27.24,"province":"湖南省","city":"邵阳市"}
]
''');

    test('唯一城市名和省份/区县完整标签可精确解析', () {
      expect(CityLocationService.findUniqueIn(sample, '上海市')?.name, '上海市');
      expect(
        CityLocationService.findUniqueIn(sample, '长宁区（上海市）')?.province,
        '上海市',
      );
    });

    test('可省略唯一行政后缀，但同名区县必须返回 null', () {
      expect(CityLocationService.findUniqueIn(sample, '上海')?.name, '上海市');
      expect(CityLocationService.findUniqueIn(sample, '长宁') , isNull);
      expect(CityLocationService.findUniqueIn(sample, '长宁区'), isNull);
    });

    test('空地点不产生默认城市', () {
      expect(CityLocationService.findUniqueIn(sample, ''), isNull);
    });
  });

}
