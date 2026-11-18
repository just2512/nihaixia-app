import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'lunar_almanac_service.dart';

/// Synchronous, side-effect-free Headless adapter for the existing local
/// almanac calculation. It does not read saved charts or personal profile data.
class AlmanacToolExecutor {
  static const String sourceId = 'local-engine:almanac';
  static const String calendarSourceId = 'package:sxwnl_spa_dart@0.18.5';
  static const String baziSourceId = 'local-engine:ziwei-ba-zi';
  static const String deityFestivalSourceId =
      'local-data:yuxiaji-deity-festivals';
  static const String chaoshanFestivalSourceId =
      'local-data:chaoshan-festivals';
  static const String resultSchemaVersion = 'almanac-structured-result-v1';
  static const String ruleVersion =
      'almanac-snapshot-contract=v1;'
      'lunar-almanac@b71c7bda3bc676b8c83f834e0109f78605409ddf;'
      'ziwei-engine@a4cbb9cd20e595cbb256e4225332eb967db89d5e;'
      'yuxiaji-deity-data@01c8a2265eae2633668c69cd5a6df13765c205ca;'
      'chaoshan-festival-data@aad101b25e2d6fad1455b25268d78234a08ed8cb;'
      'sxwnl_spa_dart@0.18.5';

  static const List<String> resultSourceIds = [
    sourceId,
    calendarSourceId,
    baziSourceId,
    deityFestivalSourceId,
    chaoshanFestivalSourceId,
  ];

  /// Create an immutable, date-addressed snapshot from the same deterministic
  /// local engine as the visible almanac page. No saved-chart personal data is
  /// read or serialized into this result.
  static Map<String, Object?> createStructuredSnapshot(DateTime selectedDate) {
    final date = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final dateText = _formatDate(date);
    final toolResult = execute({'date': dateText});
    if (toolResult.status != AssistantToolExecutionStatus.succeeded ||
        toolResult.toolId != 'almanac' ||
        !toolResult.sourceIds.contains(sourceId)) {
      throw StateError(
        'The selected almanac date did not produce a verified successful local result.',
      );
    }

    final day = getDailyAlmanac(date);
    final result = <String, Object?>{
      'solarDate': _formatDate(day.solar),
      'weekday': day.weekdayName,
      'lunarDate': day.lunarText,
      'ganzhi': <String, String>{
        'year': day.ganzhiYear,
        'month': day.ganzhiMonth,
        'day': day.ganzhiDay,
      },
      'jianChu': <String, Object?>{
        'name': day.jianChu,
        'index': day.jianChuIndex,
      },
      'pengZu': List<String>.unmodifiable(day.pengZu),
      'conflictAndDirection': <String, String>{
        'chong': day.chong,
        'sha': day.sha,
        'dayZodiac': day.dayZodiac,
        'chongZodiac': day.chongZodiac,
      },
      'yi': List<String>.unmodifiable(day.yi),
      'ji': List<String>.unmodifiable(day.ji),
      'solarTerm': <String, Object?>{
        'status': day.solarTerm == null ? 'NONE_TODAY' : 'PRESENT',
        'value': day.solarTerm,
      },
      'festivals': <String, Object?>{
        'calendarFestivals': List<String>.unmodifiable(day.festivals),
        'deityFestivals': List<String>.unmodifiable(day.deityFestivals),
        'chaoshanFestivals': List<String>.unmodifiable(day.chaoshanFestivals),
      },
      'auspiciousHours': List<String>.unmodifiable(day.jiShi),
      'directions': <String, String>{
        'caiShen': day.caiShen,
        'xiShen': day.xiShen,
        'fuShen': day.fuShen,
      },
      'personalizedOverlay': <String, Object?>{
        'included': false,
        'excluded': '页面可能基于最近保存命盘显示“本命生肖相冲”提示；该个人化显示层不属于本日期黄历计算，本快照未读取或传递保存命盘资料。',
      },
      'disclaimer': toolResult.disclaimer,
    };

    final base = <String, Object?>{
      'capabilityId': 'almanac',
      'resultSchemaVersion': resultSchemaVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': List<String>.unmodifiable(resultSourceIds),
      'input': <String, Object?>{
        'date': dateText,
        'dateConvention': '公历自然日；按本地日期字段计算，不含出生地或用户个人资料。',
      },
      'result': Map<String, Object?>.unmodifiable(result),
      'units': const <String, Object?>{
        'date': '公历日期，YYYY-MM-DD',
        'ganzhi': '正午基准；年/月/日干支沿用 App 紫微四柱接口的平太阳时口径',
        'jianChu.index': '0=建，依次至 11=闭',
        'auspiciousHours': '十二时辰名称；通胜传统规则推算',
        'directions': '传统方位名称',
        'personalizedOverlay.included': 'false 表示未读取最近保存命盘等个人化资料',
      },
      'missingFields': const <String>[],
      'displaySummary': toolResult.toConversationText(),
      'ruleVersion': ruleVersion,
    };
    final snapshotId = AiToolResultSnapshot.createStructuredId(snapshot: base);
    return Map<String, Object?>.unmodifiable({
      ...base,
      'snapshotId': snapshotId,
    });
  }

  static AssistantToolResult execute(Map<String, String> arguments) {
    if (arguments.keys.any((key) => key != 'date')) {
      return _failure(arguments, '包含未声明的查询参数，未执行计算。');
    }

    final rawDate = arguments['date'];
    final date = rawDate == null ? null : _parseDate(rawDate);
    if (date == null) {
      return _failure(arguments, '查询日期不是有效日期；请使用 YYYY-MM-DD，未执行计算。');
    }
    if (date.year < 1900 || date.year > 2100) {
      return _failure(arguments, '查询日期超出支持范围（1900-2100），未执行计算。');
    }

    final day = getDailyAlmanac(date);
    return AssistantToolResult(
      toolId: 'almanac',
      title: '每日黄历',
      values: {
        '公历': _formatDate(day.solar),
        '星期': day.weekdayName,
        '农历': day.lunarText,
        '干支': '${day.ganzhiYear}年 ${day.ganzhiMonth}月 ${day.ganzhiDay}日',
        '建除': day.jianChu,
        '彭祖百忌': day.pengZu.join('；'),
        '冲煞': '${day.chong}，${day.sha}',
        '日生肖': day.dayZodiac,
        '宜': day.yi.join('、'),
        '忌': day.ji.join('、'),
        '黄道吉时': day.jiShi.join('、'),
        '财神方位': day.caiShen,
        '喜神方位': day.xiShen,
        '福神方位': day.fuShen,
        '节气': day.solarTerm ?? '当日无交节',
        '节日': [
          ...day.festivals,
          ...day.deityFestivals,
          ...day.chaoshanFestivals,
        ].join('、'),
      },
      sourceIds: const [sourceId],
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '依据 App 本地历法与通胜规则计算，仅作传统民俗文化参考；不是事实预测或行为指令，不构成医疗、法律或投资建议。',
    );
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'almanac',
        title: '每日黄历',
        status: AssistantToolExecutionStatus.failed,
        values: {'错误': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '本次没有执行黄历计算。',
      );

  static DateTime? _parseDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || _formatDate(parsed) != raw) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
