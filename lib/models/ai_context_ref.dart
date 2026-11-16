class AiContextRef {
  const AiContextRef({
    required this.kind,
    required this.moduleId,
    required this.anchorId,
    required this.anchorVersion,
    required this.sourceId,
    this.snapshotId,
    this.ruleVersion,
    this.title,
  });

  final String kind;
  final String moduleId;
  final String anchorId;
  final String anchorVersion;
  final String sourceId;
  final String? snapshotId;
  final String? ruleVersion;
  final String? title;

  Map<String, String> toMetadata() => Map.unmodifiable({
        'kind': kind,
        'moduleId': moduleId,
        'anchorId': anchorId,
        'anchorVersion': anchorVersion,
        'sourceId': sourceId,
        if (snapshotId != null) 'snapshotId': snapshotId!,
        if (ruleVersion != null) 'ruleVersion': ruleVersion!,
        if (title != null) 'title': title!,
      });

  static Map<String, String> normalizeMetadata(Map<String, String>? value) {
    if (value == null || value.isEmpty) return const {};
    const requiredKeys = [
      'kind',
      'moduleId',
      'anchorId',
      'anchorVersion',
      'sourceId',
    ];
    if (requiredKeys.any((key) => value[key]?.trim().isNotEmpty != true)) {
      return const {};
    }
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key: entry.value,
    });
  }
}
