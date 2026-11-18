/// Closed set of contextual source kinds. Persisted metadata remains the
/// stable wire string (for example "classic" and "toolResult").
enum AiContextKind {
  classic('classic'),
  formula('formula'),
  herb('herb'),
  caseRecord('case'),
  toolResult('toolResult'),
  fieldValue('field');

  const AiContextKind(this.metadataValue);

  final String metadataValue;

  static AiContextKind? fromMetadata(String? value) {
    for (final kind in values) {
      if (kind.metadataValue == value) return kind;
    }
    return null;
  }
}

class AiContextRef {
  const AiContextRef({
    required this.kind,
    required this.moduleId,
    required this.anchorId,
    required this.anchorVersion,
    required this.sourceId,
    this.snapshotId,
    this.ruleVersion,
    this.fieldPath,
    this.title,
    this.selectedText,
  });

  final AiContextKind kind;
  final String moduleId;
  final String anchorId;
  final String anchorVersion;
  final String sourceId;
  final String? snapshotId;
  final String? ruleVersion;
  final String? fieldPath;
  final String? title;

  /// Exact raw selection for classic reading; participates in session identity.
  final String? selectedText;

  Map<String, String> toMetadata() => Map.unmodifiable({
        'kind': kind.metadataValue,
        'moduleId': moduleId,
        'anchorId': anchorId,
        'anchorVersion': anchorVersion,
        'sourceId': sourceId,
        if (snapshotId != null) 'snapshotId': snapshotId!,
        if (ruleVersion != null) 'ruleVersion': ruleVersion!,
        if (fieldPath != null) 'fieldPath': fieldPath!,
        if (title != null) 'title': title!,
        if (selectedText != null) 'selectedText': selectedText!,
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
    final kind = AiContextKind.fromMetadata(value['kind']?.trim());
    if (kind == null) return const {};

    if (kind == AiContextKind.toolResult ||
        kind == AiContextKind.fieldValue) {
      final snapshotId = value['snapshotId']?.trim();
      final ruleVersion = value['ruleVersion']?.trim();
      final anchorVersion = value['anchorVersion']?.trim();
      final fieldPath = value['fieldPath']?.trim();
      if (snapshotId == null ||
          snapshotId.isEmpty ||
          ruleVersion == null ||
          ruleVersion.isEmpty ||
          snapshotId != anchorVersion ||
          (kind == AiContextKind.fieldValue &&
              (fieldPath == null || fieldPath.isEmpty))) {
        return const {};
      }
    }

    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key:
              entry.key == 'kind' ? kind.metadataValue : entry.value,
    });
  }
  
  /// Compares a persisted context reference with the requested anchor.
  /// Every normalized field participates, including snapshot/version values.
  static bool matchesSameAnchor(
    Map<String, String>? left,
    Map<String, String>? right,
  ) {
    final normalizedLeft = normalizeMetadata(left);
    final normalizedRight = normalizeMetadata(right);
    if (normalizedLeft.isEmpty ||
        normalizedRight.isEmpty ||
        normalizedLeft.length != normalizedRight.length) {
      return false;
    }
    return normalizedRight.entries.every(
      (entry) => normalizedLeft[entry.key] == entry.value,
    );
  }
}
