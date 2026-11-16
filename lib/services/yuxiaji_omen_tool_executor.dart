import '../data/yuxiaji_omen_data.dart';
import '../models/assistant_tool_result.dart';
import 'yuxiaji_omen_time.dart';

/// Headless lookup for the local-time entry in the existing Yu Xia Ji data.
/// Special omen methods remain on the original page because they require
/// additional observed inputs (direction, shape, or manual description).
class YuxiajiOmenToolExecutor {
  static const sourceId = 'local-data:yuxiaji-omen';

  static AssistantToolResult execute(
    Map<String, String> arguments, {
    DateTime Function()? clock,
  }) {
    if (arguments.isNotEmpty) {
      return AssistantToolResult(
        toolId: 'yuxiaji_omen',
        title: '玉匣灵兆',
        status: AssistantToolExecutionStatus.failed,
        values: const {'未执行原因': '此查询只读取 App 本机时辰，不接受额外参数。'},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '参数契约不匹配；本次没有查询。',
      );
    }

    final now = (clock ?? DateTime.now)();
    final index = shiChenIndexOf(now);
    final items = kYuXiaJiShiChenOmens
        .map(
          (omen) => '${omen.name}（${omen.target}）：${omen.duanByHour[index]}',
        )
        .join('\n');

    return AssistantToolResult(
      toolId: 'yuxiaji_omen',
      title: '玉匣灵兆 · ${shiChenLabel(index)}',
      values: {
        'App 本机日期时间': now.toIso8601String(),
        '本机 UTC 偏移分钟': now.timeZoneOffset.inMinutes.toString(),
        '当前时辰': shiChenLabel(index),
        '《玉匣记》当前时辰身兆条目': items,
        '数据范围': '仅查询本地《玉匣记》十二时辰身兆文本；不包含需要额外观察输入的特殊占法。',
      },
      sourceIds: const [sourceId],
      arguments: const {},
      disclaimer:
          '传统民俗文化文本参考；不是科学预测、吉凶指令或医学诊断。面热、眼跳、耳鸣、心惊等条目不构成疾病判断、病因判断或健康风险评估。',
    );
  }
}
