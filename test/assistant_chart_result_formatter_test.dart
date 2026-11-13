import 'package:flutter_test/flutter_test.dart';
import 'package:ziwei_core/ziwei_core.dart';

import 'package:nihaisha_app/services/assistant_chart_result_formatter.dart';
import 'package:nihaisha_app/services/bazi_service.dart';
import 'package:nihaisha_app/services/ziwei_engine.dart';
import 'package:nihaisha_app/services/ziwei_interpretation.dart';

void main() {
  test('八字回传摘要包含 App 已计算的详批与大运字段', () {
    final solar = DateTime(1995, 8, 16, 12);
    final location = Location(120, 30);
    final result = computeBaZiPaipan(
      solar,
      isMale: true,
      useTrueSolarTime: false,
      ratHourMode: false,
      location: location,
    );
    final fortune = computeBaZiFortune(
      solar,
      isMale: true,
      location: location,
      useTrueSolarTime: false,
      ratHourMode: false,
    );

    final text = formatBaZiChartForAssistant(
      solar: solar,
      isMale: true,
      useTrueSolarTime: false,
      distinguishZiShi: false,
      locationDescription: '测试地点（东经120°，北纬30°）',
      result: result,
      fortune: fortune,
    );

    expect(text, contains('结果来源：App 本地确定性排盘'));
    expect(text, contains('四柱：\${result.bazi.year} \${result.bazi.month} \${result.bazi.day} \${result.bazi.time}'));
    expect(text, contains('日主：\${result.analysis.dayMaster}'));
    expect(text, contains('格局：\${result.analysis.pattern}'));
    expect(text, contains('日主强弱：\${result.analysis.strengthLevel}'));
    expect(text, contains('五行分布状态：'));
    expect(text, contains('用神：\${result.analysis.favorable.join('、')}'));
    expect(text, contains('忌神：\${result.analysis.unfavorable.join('、')}'));
    expect(text, contains('第\${fortune.decades.first.index}步：'));
    expect(text, contains('区分排盘事实与 AI 归纳'));
    expect(text, isNot(contains('strengthScore')));
    expect(text, isNot(contains('(+0.5)')));
  });

  test('紫微回传摘要包含十二宫、生年四化和 App 已有整体/大限解读', () {
    final solar = DateTime(1990, 6, 15, 10);
    final chart = calculateZiweiChart(
      solar: solar,
      gender: Gender.male,
      location: Location(120, 30),
      useTrueSolarTime: false,
    );

    final text = formatZiweiChartForAssistant(
      solar: solar,
      useTrueSolarTime: false,
      distinguishZiShi: false,
      locationDescription: '测试地点（东经120°，北纬30°）',
      chart: chart,
    );

    expect(text, contains('结果来源：App 本地确定性紫微排盘引擎'));
    expect(text, contains('十二宫星曜'));
    for (final palace in chart.palaces) {
      expect(text, contains(palace.roleLabel));
      expect(text, contains(palace.branchLabel));
    }
    expect(text, contains('生年四化：'));
    expect(text, contains(summarizeOverall(chart)));
    expect(text, contains(summarizeDecades(chart).first));
    expect(text, contains('区分哪些是 App 排盘字段'));
    expect(text, isNot(contains('身体留意')));
    expect(text, isNot(contains('健康提醒清单')));
  });
}
