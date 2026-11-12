import '../models/assistant_tool_result.dart';
import 'yunqi_engine.dart';

/// Synchronous, side-effect-free Headless adapter for the existing YunQiEngine.
/// It deliberately reuses the page's year/date convention and result wording.
class YunQiToolExecutor {
  static const String sourceId = 'local-engine:yunqi';

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
