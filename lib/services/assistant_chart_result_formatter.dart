import 'bazi_service.dart';
import 'ziwei_engine.dart';
import 'ziwei_interpretation.dart';

/// Produces the deterministic App result payload that is handed back to the
/// local assistant. It deliberately excludes internal numeric weights.
String formatBaZiChartForAssistant({
  required DateTime solar,
  required bool isMale,
  required bool useTrueSolarTime,
  required bool distinguishZiShi,
  required String locationDescription,
  required BaZiPaipan result,
  BaZiFortune? fortune,
}) {
  final pillars = [
    result.bazi.year,
    result.bazi.month,
    result.bazi.day,
    result.bazi.time,
  ];
  final analysis = result.analysis;
  final factorLabels = analysis.strengthFactors
      .map((value) => value.replaceAll(RegExp(r'\s*\([+-]?\d+(?:\.\d+)?\)'), ''))
      .toList(growable: false);
  const pillarLabels = ['年柱', '月柱', '日柱', '时柱'];

  final lines = <String>[
    '【八字排盘完整结果】',
    '结果来源：App 本地确定性排盘与详批计算；不是 AI 自行排盘。',
    '出生时间：${solar.year}-${solar.month.toString().padLeft(2, '0')}-${solar.day.toString().padLeft(2, '0')} ${solar.hour.toString().padLeft(2, '0')}:${solar.minute.toString().padLeft(2, '0')}',
    '性别：${isMale ? '男' : '女'}；出生地：${locationDescription.isEmpty ? '未指定（使用引擎默认地点）' : locationDescription}',
    '真太阳时：${useTrueSolarTime ? '开启' : '关闭'}；早晚子时区分：${distinguishZiShi ? '开启' : '关闭'}',
    '出生农历：${result.lunarText}',
    '四柱：${pillars.join(' ')}',
    '十神（年/月/日/时）：${result.tenGods.join(' / ')}',
    '纳音（年/月/日/时）：${pillars.map(nayinOfPillar).join(' / ')}',
    '旬空：${result.kongWang.isEmpty ? 'MISSING' : result.kongWang.join('、')}',
    '各柱旬空：${result.kongWangPillars.join(' / ')}',
    '刑冲合害关系：${result.relations.isEmpty ? '未检出' : result.relations.join('；')}',
    '长生十二神（年/月/日/时）：${result.twelveStages.join(' / ')}',
    '各柱自坐十二神：${result.selfStages.join(' / ')}',
    '胎元：${result.taiYuan}；胎息：${result.taiXi}',
    '各柱藏干十神：${[
      for (var i = 0; i < result.hiddenTenGods.length; i++)
        '${pillarLabels[i]}：${result.hiddenTenGods[i].isEmpty ? 'MISSING' : result.hiddenTenGods[i].join('、')}',
    ].join('；')}',
    '',
    '【App 详批引擎结果】',
    '日主：${analysis.dayMaster}',
    '格局：${analysis.pattern}',
    '格局说明：${analysis.patternDesc}',
    '日主强弱：${analysis.strengthLevel}',
    '强弱判断依据：${factorLabels.isEmpty ? 'MISSING' : factorLabels.join('；')}',
    '五行分布状态：${analysis.fiveElements.map((item) => '${item.element}：${item.status}').join('；')}',
    '用神：${analysis.favorable.isEmpty ? 'MISSING' : analysis.favorable.join('、')}',
    '忌神：${analysis.unfavorable.isEmpty ? 'MISSING' : analysis.unfavorable.join('、')}',
    'App 现有建议字段：${analysis.suggestion}',
    '神煞：${analysis.shensha.isEmpty ? '未检出' : analysis.shensha.map((item) => '${item.name}（${item.pillar}柱，${item.pos}）').join('、')}',
    '',
    '【大运】',
    if (fortune == null) '大运：MISSING'
    else '起运：${fortune.startAge.toStringAsFixed(1)} 岁；交运时间：${fortune.qiYunTime}',
    if (fortune == null)
      '大运明细：MISSING'
    else
      ...fortune.decades.map((item) =>
          '第${item.index}步：${item.ganZhi}，${item.startAge}–${item.endAge}岁；所辖流年：${item.years.map((year) => '${year.year} ${year.ganZhi}').join('、')}'),
    '',
    '解读要求：请基于以上 App 已计算字段做归纳，解释强弱、格局、五行和大运之间的关系；区分排盘事实与 AI 归纳，不得自行改动四柱或补造缺失字段。',
    '边界：传统命理文化学习参考，不是科学预测，不用于医疗、法律或投资决策。',
  ];
  return lines.join('\n');
}

/// Full deterministic Ziwei result plus the interpretation templates already
/// produced by the App. Health-watch predictions are intentionally excluded.
String formatZiweiChartForAssistant({
  required DateTime solar,
  required bool useTrueSolarTime,
  required bool distinguishZiShi,
  required String locationDescription,
  required ZiweiChart chart,
  FlowYearMark? flowYear,
  FlowMonthMark? flowMonth,
  FlowDayMark? flowDay,
}) {
  final life = chart.palaces.firstWhere((palace) => palace.isLife);
  final body = chart.palaces.firstWhere((palace) => palace.isBody);
  final palaceLines = chart.palaces.map((palace) {
    final stars = palace.stars.map(starDisplayText).toList(growable: false);
    final markers = [
      if (palace.isLife) '命宫',
      if (palace.isBody) '身宫',
    ];
    return '${palace.roleLabel}（${palace.branchLabel}）${markers.isEmpty ? '' : '〔${markers.join('、')}〕'}：${stars.isEmpty ? '无星曜条目' : stars.join('、')}';
  }).toList(growable: false);
  final decadeInterpretations = summarizeDecades(chart);
  String palaceRole(int index) =>
      chart.palaces.firstWhere((palace) => palace.index == index).roleLabel;
  final flowYearLines = flowYear == null
      ? const <String>[]
      : <String>[
          '流年：${flowYear.year}年 ${flowYear.ganzhi}',
          '流年命宫：${palaceRole(flowYear.mingIndex)}；太岁宫：${palaceRole(flowYear.taiSuiIndex)}',
          '流曜落宫：${flowYear.flowStars.entries.map((entry) => '${palaceRole(entry.key)}：${entry.value.join('、')}').join('；')}',
        ];
  final flowMonthLines = flowMonth == null
      ? const <String>[]
      : <String>[
          '流月：${flowMonth.date.year}-${flowMonth.date.month.toString().padLeft(2, '0')}-${flowMonth.date.day.toString().padLeft(2, '0')}；农历${flowMonth.isLeap ? '闰' : ''}${flowMonth.month}月 ${flowMonth.ganzhi}',
          '流月命宫：${flowMonth.roleLabel}；宫位地支索引：${flowMonth.mingIndex}',
        ];
  final flowDayLines = flowDay == null
      ? const <String>[]
      : <String>[
          '流日：${flowDay.date.year}-${flowDay.date.month.toString().padLeft(2, '0')}-${flowDay.date.day.toString().padLeft(2, '0')} ${flowDay.ganzhi}',
          '流日命宫：${flowDay.roleLabel}；宫位地支索引：${flowDay.mingIndex}',
        ];
  final sihua = chart.sihua
      .map((item) => '化${item.typeLabel}：${item.starLabelName}')
      .join('；');

  final lines = <String>[
    '【紫微斗数排盘完整结果】',
    '结果来源：App 本地确定性紫微排盘引擎；不是 AI 自行起盘。',
    '出生时间：${solar.year}-${solar.month.toString().padLeft(2, '0')}-${solar.day.toString().padLeft(2, '0')} ${solar.hour.toString().padLeft(2, '0')}:${solar.minute.toString().padLeft(2, '0')}',
    '性别：${chart.genderLabel}；出生地：${locationDescription.isEmpty ? '未指定（使用引擎默认地点）' : locationDescription}',
    '真太阳时：${useTrueSolarTime ? '开启' : '关闭'}；早晚子时区分：${distinguishZiShi ? '开启' : '关闭'}',
    '出生四柱：${chart.baziFull}；出生农历：${chart.lunarText}',
    '五行局：${chart.elementBureauLabel}',
    '命宫：${life.roleLabel}（${life.branchLabel}）；身宫：${body.roleLabel}（${body.branchLabel}）',
    '命主：${chart.mingZhuLabel ?? 'MISSING'}；身主：${chart.shenZhuLabel ?? 'MISSING'}',
    '生年四化：${sihua.isEmpty ? 'MISSING' : sihua}',
    '',
    '【十二宫星曜】',
    ...palaceLines,
    '',
    '【App 现有规则模板解读】',
    '整体运势：${summarizeOverall(chart)}',
    '大限区间：${chart.decades.map((item) => '第${item.index}限 ${item.rangeLabel} 行${item.roleLabel}（${item.ganzhiLabel}）').join('；')}',
    '大限解读：${decadeInterpretations.isEmpty ? 'MISSING' : decadeInterpretations.join('；')}',
    if (flowYear != null || flowMonth != null || flowDay != null) ...[
      '',
      '【本次已选择的流年/流月/流日】',
      ...flowYearLines,
      ...flowMonthLines,
      ...flowDayLines,
      '以上仅记录当前页面已选择并由 App 计算的流层字段；没有选择的流层不补算。',
    ],
    '',
    '解读要求：请先归纳命宫、身宫、生年四化和十二宫之间的主要关系，再结合大限作分层解释；明确哪些是 App 排盘字段、哪些是 App 规则模板、哪些是 AI 归纳。缺失字段保持 MISSING，不自行重排或补造。',
    '边界：传统术数与民俗文化学习参考，不是科学预测，不用于医疗、法律或投资决策；不要把疾厄宫或星曜解释成医学诊断。',
  ];
  return lines.join('\n');
}

/// Returns a complete, structured Ziwei result snapshot payload.
///
/// This is the deterministic engine output, not a rendering of UI text.
/// [displaySummary] is kept as a separate optional reading aid and is not used
/// as the authoritative result data.
const ziweiStructuredResultRuleVersion =
    'ziwei_core@0.13.0;app-formatter=ziwei-result-v1;structured-result=v1';

Map<String, Object?> serializeZiweiStarForAssistant(ZiweiStar star) =>
    Map<String, Object?>.unmodifiable({
      'starKey': star.key,
      'name': star.label,
      'category': star.isMajor
          ? '主星'
          : star.isLucky
              ? '吉星'
              : star.isBad
                  ? '煞星'
                  : '杂曜',
      'starType': star.type.name,
      'brightness': star.brightness,
      'transformation':
          star.sihua == null ? null : star.sihuaText,
      'displayText': starDisplayText(star),
    });

Map<String, Object?> buildZiweiStructuredResultForAssistant({
  required DateTime solar,
  required bool useTrueSolarTime,
  required bool distinguishZiShi,
  required String locationDescription,
  required double longitude,
  required double latitude,
  required ZiweiChart chart,
  FlowYearMark? flowYear,
  FlowMonthMark? flowMonth,
  FlowDayMark? flowDay,
}) {
  final life = chart.palaces.firstWhere((palace) => palace.isLife);
  final body = chart.palaces.firstWhere((palace) => palace.isBody);
  final palaces = chart.palaces
      .toList(growable: false)
    ..sort((a, b) => a.index.compareTo(b.index));
  final palaceRecords = palaces
      .map((palace) => Map<String, Object?>.unmodifiable({
            'physicalBranchIndex': palace.index,
            'roleLabel': palace.roleLabel,
            'branchLabel': palace.branchLabel,
            'stemLabel': palace.stemLabel,
            'ganzhiLabel': palace.ganzhiLabel,
            'isLife': palace.isLife,
            'isBody': palace.isBody,
            'stars': palace.stars
                .map(serializeZiweiStarForAssistant)
                .toList(growable: false),
          }))
      .toList(growable: false);
  final decadeRecords = chart.decades
      .map((decade) => Map<String, Object?>.unmodifiable({
            'index': decade.index,
            'startAge': decade.startTime,
            'endAge': decade.endTime,
            'roleLabel': decade.roleLabel,
            'ganzhiLabel': decade.ganzhiLabel,
          }))
      .toList(growable: false);
  final sihuaRecords = chart.sihua
      .map((item) => Map<String, Object?>.unmodifiable({
            'type': item.type.name,
            'typeLabel': item.typeLabel,
            'starKey': item.starKey,
            'starLabel': item.starLabelName,
          }))
      .toList(growable: false);
  final flow = <String, Object?>{
    'year': flowYear == null
        ? null
        : {
            'year': flowYear.year,
            'ganzhi': flowYear.ganzhi,
            'mingPhysicalBranchIndex': flowYear.mingIndex,
            'taiSuiPhysicalBranchIndex': flowYear.taiSuiIndex,
            'starsByPhysicalBranch': {
              for (final entry in flowYear.flowStars.entries)
                entry.key.toString(): List<String>.unmodifiable(entry.value),
            },
          },
    'month': flowMonth == null
        ? null
        : {
            'date': flowMonth.date.toIso8601String(),
            'year': flowMonth.year,
            'lunarMonth': flowMonth.month,
            'isLeapMonth': flowMonth.isLeap,
            'ganzhi': flowMonth.ganzhi,
            'mingPhysicalBranchIndex': flowMonth.mingIndex,
            'illnessPhysicalBranchIndex': flowMonth.illnessIndex,
            'mingPalaceRole': flowMonth.roleLabel,
          },
    'day': flowDay == null
        ? null
        : {
            'date': flowDay.date.toIso8601String(),
            'ganzhi': flowDay.ganzhi,
            'mingPhysicalBranchIndex': flowDay.mingIndex,
            'illnessPhysicalBranchIndex': flowDay.illnessIndex,
            'mingPalaceRole': flowDay.roleLabel,
          },
  };
  final result = <String, Object?>{
    'bazi': {
      'yearPillar': chart.baziYear,
      'monthPillar': chart.baziMonth,
      'dayPillar': chart.baziDay,
      'hourPillar': chart.baziTime,
      'full': chart.baziFull,
    },
    'lunar': {
      'text': chart.lunarText,
      'month': chart.lunarMonth,
      'isLeapMonth': chart.lunarIsLeap,
      'monthDisplay': chart.lunarMonthDisplay,
    },
    'elementBureau': chart.elementBureauLabel,
    'lifePalace': {
      'physicalBranchIndex': life.index,
      'roleLabel': life.roleLabel,
      'branchLabel': life.branchLabel,
    },
    'bodyPalace': {
      'physicalBranchIndex': body.index,
      'roleLabel': body.roleLabel,
      'branchLabel': body.branchLabel,
    },
    'mingZhu': chart.mingZhuLabel,
    'shenZhu': chart.shenZhuLabel,
    'sihua': sihuaRecords,
    'palacesByPhysicalBranch': palaceRecords,
    'decades': decadeRecords,
    'selectedFlow': flow,
    'interpretationTemplates': {
      'overall': summarizeOverall(chart),
      'decades': summarizeDecades(chart),
    },
  };
  final input = <String, Object?>{
    'solar': solar.toIso8601String(),
    'gender': chart.genderLabel,
    'location': {
      'description': locationDescription,
      'longitude': longitude,
      'latitude': latitude,
    },
    'useTrueSolarTime': useTrueSolarTime,
    'distinguishZiShi': distinguishZiShi,
  };
  final missingFields = <String>[
    if (chart.mingZhuLabel == null) 'result.mingZhu',
    if (chart.shenZhuLabel == null) 'result.shenZhu',
    if (chart.sihua.isEmpty) 'result.sihua',
  ];
  return Map<String, Object?>.unmodifiable({
    'capabilityId': 'ziwei',
    'sourceIds': const ['local-engine:ziwei-core@0.13.0'],
    'executionStatus': 'SUCCESS',
    'ruleVersion': ziweiStructuredResultRuleVersion,
    'resultSchemaVersion': 'ziwei-structured-result-v1',
    'input': input,
    'result': result,
    'units': const {
      'result.decades.startAge': '虚岁',
      'result.decades.endAge': '虚岁',
      'input.location.longitude': '度',
      'input.location.latitude': '度',
      'result.lunar.month': '农历月',
      'result.palacesByPhysicalBranch[].stars[].brightness':
          '星曜亮度等级（离散标签）',
      'result.palacesByPhysicalBranch[].stars[].transformation':
          '生年四化类别（离散标签）',
      'result.sihua[].typeLabel': '四化类别（离散标签）',
    },
    'missingFields': missingFields,
    'displaySummary': formatZiweiChartForAssistant(
      solar: solar,
      useTrueSolarTime: useTrueSolarTime,
      distinguishZiShi: distinguishZiShi,
      locationDescription: locationDescription,
      chart: chart,
      flowYear: flowYear,
      flowMonth: flowMonth,
      flowDay: flowDay,
    ),
  });
}
