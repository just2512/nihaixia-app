import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_calculation_service.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_engine.dart' as engine;

void main() {
  test('local timestamp parser accepts only real local wall-clock times', () {
    expect(
      ZiWuLiuZhuCalculationService.parseLocalAt('2026-11-14T10:30'),
      DateTime(2026, 11, 14, 10, 30),
    );
    for (final invalid in [
      '2026-02-30T10:30',
      '1899-12-31T23:00',
      '2101-01-01T00:00',
      '2026-11-14T24:00',
      '2026-11-14T10:60',
      '2026-11-14T10:30Z',
      '2026-11-14T10:30+08:00',
      '2026/11/14 10:30',
    ]) {
      expect(
        ZiWuLiuZhuCalculationService.parseLocalAt(invalid),
        isNull,
        reason: invalid,
      );
    }
  });

  test('shichen boundaries preserve the legacy 23:00 Zi hour change', () {
    expect(
      ZiWuLiuZhuCalculationService.shichenIndex(DateTime(2026, 11, 14, 22, 59)),
      11,
    );
    expect(
      ZiWuLiuZhuCalculationService.shichenIndex(DateTime(2026, 11, 14, 23, 0)),
      0,
    );
    expect(
      ZiWuLiuZhuCalculationService.shichenIndex(DateTime(2026, 11, 15, 0, 59)),
      0,
    );
    expect(
      ZiWuLiuZhuCalculationService.shichenIndex(DateTime(2026, 11, 15, 1, 0)),
      1,
    );
  });

  test('shared summary matches existing engine output and all four original methods', () {
    final at = DateTime(2026, 10, 8, 12, 0);
    final result = ZiWuLiuZhuCalculationService.calculate(at);
    final day = engine.calcDayGanZhi(at);
    final hour = engine.calcHourGanZhi(day.dayGan, at.hour, at.minute);
    final najia = engine.najiaOpen(day.dayGan, hour.hourGan, hour.hourZhi) ??
        engine.najiaHeRi(day.dayGan, hour.hourGan, hour.hourZhi);
    final linggui = engine.lingguiOpen(
      day.dayGan,
      day.dayZhi,
      hour.hourGan,
      hour.hourZhi,
    );
    final feiteng = engine.feitengOpen(hour.hourGan);

    expect(result.dayGanZhi, '${engine.ganName(day.dayGan)}${engine.zhiName(day.dayZhi)}');
    expect(result.hourGanZhi, '${engine.ganName(hour.hourGan)}${engine.zhiName(hour.hourZhi)}');
    expect(result.dayGanZhi, '乙卯');
    expect(result.shichen, '午');
    expect(result.meridian, '心经');
    expect(result.benXue, '少府');
    expect(result.values['纳甲穴位'], najia?['point']);
    expect(result.values['灵龟主穴'], (linggui['gua'] as List<String>)[1]);
    expect(result.values['灵龟配穴'], linggui['peidui']);
    expect(result.values['飞腾开穴'], feiteng?[1]);
    expect(result.values['飞腾卦'], feiteng?[0]);
    expect(result.summary, contains('纳子法：'));
    expect(result.summary, contains('纳甲法：'));
    expect(result.summary, contains('灵龟八法：'));
    expect(result.summary, contains('飞腾八法：'));
    expect(result.summary, contains('默认经纬度 120E/30N，子时按 23:00 换日'));
    expect(result.summary, contains('不代表个体诊疗建议'));
  });

  test('legacy NaZi reference tables are exposed from the shared source', () {
    expect(
      ZiWuLiuZhuCalculationService.benXueByMeridian['肝经'],
      '大敦',
    );
    expect(
      ZiWuLiuZhuCalculationService.benXueByMeridian['大肠经'],
      '商阳',
    );
    expect(
      ZiWuLiuZhuCalculationService.benXueByMeridian['心包经'],
      '劳宫',
    );
    expect(
      ZiWuLiuZhuCalculationService.benXueByMeridian['三焦经'],
      '支沟',
    );
    expect(
      ZiWuLiuZhuCalculationService.wuMenInfo('乙'),
      '乙庚合化金（大敦+商阳）',
    );
    expect(
      ZiWuLiuZhuCalculationService.zhiToMeridian['子'],
      ('胆经', '23:00–01:00'),
    );
  });
}
