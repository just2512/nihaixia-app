/// Typed result returned by an in-app tool to the unified assistant timeline.
class AssistantToolResult {
  const AssistantToolResult({
    required this.toolId,
    required this.title,
    required this.values,
    this.disclaimer,
  });

  final String toolId;
  final String title;
  final Map<String, String> values;
  final String? disclaimer;

  String toConversationText() {
    final lines = <String>[
      '工具：$title',
      for (final entry in values.entries)
        '${entry.key}：${entry.value.isEmpty ? 'MISSING' : entry.value}',
      if (disclaimer != null && disclaimer!.trim().isNotEmpty)
        '说明：${disclaimer!.trim()}',
    ];
    return lines.join('\n');
  }
}
