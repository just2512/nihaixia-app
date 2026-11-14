import 'dart:math';

import '../data/sanshan_lingqian_data.dart';
import '../models/assistant_tool_result.dart';

/// Headless access to the existing 92-sign catalogue.
///
/// The App, not the model, chooses the random index. The same result mapper is
/// also used by the existing page handoff so both entry points return identical
/// sign text and provenance.
class SanshanLingqianToolExecutor {
  static const String dataSourcePrefix = 'local-data:sanshan-lingqian:';

  static LingqianSign draw({Random? random}) {
    final source = random ?? Random();
    final index = source.nextInt(kSanShanLingqian.length);
    return kSanShanLingqian[index];
  }

  static AssistantToolResult resultForSign(LingqianSign sign) {
    return AssistantToolResult(
      toolId: 'sanshan_lingqian',
      title: '三山国王灵签',
      values: {
        '签号': sign.id.toString(),
        '签题': sign.title,
        '签诗': sign.verse,
        '签级': sign.luck.label,
        '签谱范围': '本地三山国王祖庙传承 92 签签谱',
      },
      sourceIds: ['$dataSourcePrefix${sign.id}'],
      disclaimer: '潮汕客家民间信仰与签谱文化参考，不是现实吉凶保证或决策依据。',
    );
  }

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.isNotEmpty) {
      return AssistantToolResult(
        toolId: 'sanshan_lingqian',
        title: '三山国王灵签',
        status: AssistantToolExecutionStatus.failed,
        values: const {'未执行原因': '本工具不接受模型指定签号或其他参数；签号只能由 App 本地抽签生成。'},
        arguments: Map.unmodifiable(arguments),
        disclaimer: '参数契约未通过；本次没有执行抽签。',
      );
    }
    return resultForSign(draw());
  }
}
