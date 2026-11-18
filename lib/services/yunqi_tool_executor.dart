import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'yunqi_engine.dart';

/// Synchronous, side-effect-free Headless adapter for the existing YunQiEngine.
/// It deliberately reuses the page's year/date convention and result wording.
class YunQiToolExecutor {
  static const String sourceId = 'local-engine:yunqi';
  static const String resultSchemaVersion = 'yunqi-structured-result-v1';
  static const String ruleVersion =
      'yunqi-engine@f8ba8f7e48c492567a28fb5735d9187d2bdbb91e;'
      'yunqi-literature@97e628d79f28a70a5468a34e0e80e8f60130ef52;'
      'schema=$resultSchemaVersion';

  static Map<String, Object?> createStructuredSnapshot(DateTime selectedDate) {
    final date = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final dateText = _formatDate(date);
    final toolResult = execute({'date': dateText});
    if (toolResult.status != AssistantToolExecutionStatus.succeeded ||
        toolResult.toolId != 'yunqi' ||
        !toolResult.sourceIds.contains(sourceId)) {
      throw StateError('The selected YunQi date did not produce a verified successful tool result.');
    }
    final result = <String, Object?>{
      for (final entry in toolResult.values.entries)
        entry.key: entry.value.trim().isEmpty ? 'MISSING' : entry.value,
    };
    final missingFields = <String>[
      for (final entry in toolResult.values.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];
    final base = <String, Object?>{
      'capabilityId': 'yunqi',
      'resultSchemaVersion': resultSchemaVersion,
      'executionStatus': 'SUCCESS',
      'sourceIds': List<String>.unmodifiable(toolResult.sourceIds),
      'input': Map<String, Object?>.unmodifiable({
        'date': dateText,
        'calendarYear': YunQiEngine.calendarYearOf(date),
        'yearConvention': '当前 App 页面采用公历年口径',
      }),
      'result': Map<String, Object?>.unmodifiable(result),
      'units': const <String, Object?>{
        'date': '公历日期，YYYY-MM-DD',
        'calendarYear': '公历年；不等同于立春口径的运气年',
      },
      'missingFields': List<String>.unmodifiable(missingFields),
      'displaySummary': toolResult.toConversationText(),
      'ruleVersion': ruleVersion,
    };
    final snapshotId = AiToolResultSnapshot.createStructuredId(snapshot: base);
    return Map<String, Object?>.unmodifiable({...base, 'snapshotId': snapshotId});
  }

  static AssistantToolResult execute(
    Map<String, String> arguments, {
    DateTime? now,
  }) {
    if (arguments.keys.any((key) => key != 'date')) {
      return _failure(arguments, '包含未声明的推算参数，未执行计算。');
    }

    final rawDate = arguments['date'];
    final selectedDate = rawDate == null
        ? (now ?? DateTime.now())
        : _parseDate(rawDate);
    if (selectedDate == null) {
      return _failure(arguments, '推算日期无效；请使用 YYYY-MM-DD，未执行计算。');
    }
    if (selectedDate.year < 1900 || selectedDate.year > 2100) {
      return _failure(arguments, '推算日期超出页面支持范围（1900-2100），未执行计算。');
    }

    final date = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final dateText = _formatDate(date);
    final data = YunQiEngine.yearGanzhi(YunQiEngine.calendarYearOf(date));

    return AssistantToolResult(
      toolId: 'yunqi',
      title: '五运六气推算',
      values: {
        '推算日期': dateText,
        '运气年': '${data.ganZhi}年（${data.shengXiao}）',
        '岁运': '${data.yun}运${data.taiGuo ? '太过' : '不及'}',
        '司天': data.siTian,
        '在泉': data.zaiQuan,
        '岁运病候': data.yunBingText,
        '司天病候': data.siTianBingText,
        '《内经》大论原文': data.jz60['SAME'] ?? '',
      },
      sourceIds: const [sourceId],
      arguments: Map<String, String>.unmodifiable(arguments),
      disclaimer: '按 App 本地五运六气引擎生成；仅供理论学习，不构成医疗建议。',
    );
  }

  static DateTime? _parseDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || _formatDate(parsed) != raw) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String reason,
  ) =>
      AssistantToolResult(
        toolId: 'yunqi',
        title: '五运六气推算',
        status: AssistantToolExecutionStatus.failed,
        values: {'错误': reason},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数校验未通过；本次没有执行推算。',
      );
}
