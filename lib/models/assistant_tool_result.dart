/// Execution state of a tool invocation. NO_RESULT is distinct from success.
enum AssistantToolExecutionStatus { succeeded, noResult, failed }

/// Typed result returned by an in-app tool to the unified assistant timeline.
class AssistantToolResult {
  const AssistantToolResult({
    required this.toolId,
    required this.title,
    required this.values,
    this.disclaimer,
    this.sourceIds = const [],
    this.status = AssistantToolExecutionStatus.succeeded,
  });

  final String toolId;
  final String title;
  final Map<String, String> values;
  final String? disclaimer;
  final AssistantToolExecutionStatus status;
  /// Stable local/source references used to trace the execution result.
  /// Empty means the tool did not provide a source identifier (MISSING).
  final List<String> sourceIds;

  String get statusLabel => switch (status) {
        AssistantToolExecutionStatus.succeeded => 'SUCCEEDED',
        AssistantToolExecutionStatus.noResult => 'NO_RESULT',
        AssistantToolExecutionStatus.failed => 'FAILED',
      };

  List<String> validateFor(String expectedToolId) {
    final errors = <String>[];
    if (toolId != expectedToolId) {
      errors.add('工具结果标识不匹配：$toolId != $expectedToolId');
    }
    if (title.trim().isEmpty) errors.add('工具结果缺少标题');
    if (status == AssistantToolExecutionStatus.succeeded && values.isEmpty) {
      errors.add('成功的工具结果缺少结构化输出字段');
    }
    if (sourceIds.any((id) => id.trim().isEmpty)) {
      errors.add('工具结果包含空来源标识');
    }
    return List.unmodifiable(errors);
  }

  String toConversationText() {
    final lines = <String>[
      '工具：$title',
      '执行状态：' + statusLabel,
      for (final entry in values.entries)
        '${entry.key}：${entry.value.isEmpty ? 'MISSING' : entry.value}',
      '来源标识：${sourceIds.isEmpty ? 'MISSING' : sourceIds.join('、')}',
      if (disclaimer != null && disclaimer!.trim().isNotEmpty)
        '说明：${disclaimer!.trim()}',
    ];
    return lines.join('\n');
  }
}
