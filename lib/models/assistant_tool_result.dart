/// Execution state of a tool invocation. NO_RESULT is distinct from success.
enum AssistantToolExecutionStatus { succeeded, noResult, failed, cancelled }

/// Typed result returned by an in-app tool to the unified assistant timeline.
class AssistantToolResult {
  const AssistantToolResult({
    required this.toolId,
    required this.title,
    required this.values,
    this.disclaimer,
    this.sourceIds = const [],
    this.arguments = const {},
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
  /// Exact, validated arguments used to execute this tool invocation.
  final Map<String, String> arguments;

  AssistantToolResult withArguments(Map<String, String> fallback) {
    return AssistantToolResult(
      toolId: toolId,
      title: title,
      values: values,
      disclaimer: disclaimer,
      sourceIds: sourceIds,
      arguments: arguments.isEmpty ? Map.unmodifiable(fallback) : arguments,
      status: status,
    );
  }

  String get statusLabel => switch (status) {
        AssistantToolExecutionStatus.succeeded => 'SUCCEEDED',
        AssistantToolExecutionStatus.noResult => 'NO_RESULT',
        AssistantToolExecutionStatus.failed => 'FAILED',
        AssistantToolExecutionStatus.cancelled => 'CANCELLED',
      };

  List<String> validateArgumentsMatch(Map<String, String> expectedArguments) {
    if (_sameArguments(arguments, expectedArguments)) return const [];
    return const ['工具结果参数与实际调用参数不一致'];
  }

  bool _sameArguments(
    Map<String, String> actual,
    Map<String, String> expected,
  ) {
    if (actual.length != expected.length) return false;
    return expected.entries.every((entry) => actual[entry.key] == entry.value);
  }

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
    if (arguments.keys.any((key) => key.trim().isEmpty)) {
      errors.add('工具结果包含空参数名称');
    }
    return List.unmodifiable(errors);
  }

  String toConversationText() {
    final lines = <String>[
      '工具：$title',
      '执行状态：' + statusLabel,
      '执行参数：' + (arguments.isEmpty
          ? 'MISSING'
          : arguments.entries.map((entry) => '${entry.key}=${entry.value}').join('；')),
      for (final entry in values.entries)
        '${entry.key}：${entry.value.isEmpty ? 'MISSING' : entry.value}',
      '来源标识：${sourceIds.isEmpty ? 'MISSING' : sourceIds.join('、')}',
      if (disclaimer != null && disclaimer!.trim().isNotEmpty)
        '说明：${disclaimer!.trim()}',
    ];
    return lines.join('\n');
  }
}
