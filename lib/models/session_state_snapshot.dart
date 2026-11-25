/// Provenance categories frozen by the five-layer runtime contract.
enum SessionFactProvenance {
  userOriginal,
  userConfirmed,
  modelInferred,
  appResult,
  sourceReference,
}

enum SessionStateStatus {
  restored,
  partial,
  sessionMismatch,
  unknown,
}

/// One bounded, immutable fact owned by exactly one assistant session.
class SessionStateFact {
  SessionStateFact({
    required this.factId,
    required this.key,
    required Object value,
    required this.provenance,
    List<String> sourceIds = const [],
  })  : value = _freezeSessionValue(value),
        sourceIds = List.unmodifiable(sourceIds) {
    if (factId.trim().isEmpty) {
      throw ArgumentError.value(factId, 'factId', 'Must not be empty');
    }
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'Must not be empty');
    }
    if (sourceIds.any((sourceId) => sourceId.trim().isEmpty)) {
      throw ArgumentError.value(sourceIds, 'sourceIds', 'Must not contain empty IDs');
    }
  }

  final String factId;
  final String key;
  final Object value;
  final SessionFactProvenance provenance;
  final List<String> sourceIds;
}

/// A lightweight pointer to a source; source正文 is deliberately not copied.
class SessionEvidenceReference {
  const SessionEvidenceReference({
    required this.sourceId,
    this.sourceVersion = 'UNKNOWN',
    this.evidenceId,
    this.chunkId,
  });

  final String sourceId;
  final String sourceVersion;
  final String? evidenceId;
  final String? chunkId;
}

/// Read-only cross-layer memory contract. This is not Native KV cache or a
/// replacement transcript; it is a structured projection of existing stores.
class SessionStateSnapshot {
  SessionStateSnapshot({
    required this.sessionId,
    required this.revision,
    required this.status,
    required List<SessionStateFact> facts,
    required List<SessionEvidenceReference> evidenceReferences,
    this.activeTaskId,
    this.omittedUserMessageCount = 0,
    List<String> diagnostics = const [],
  })  : facts = List.unmodifiable(facts),
        evidenceReferences = List.unmodifiable(evidenceReferences),
        diagnostics = List.unmodifiable(diagnostics);

  final int sessionId;
  final String revision;
  final SessionStateStatus status;
  final List<SessionStateFact> facts;
  final List<SessionEvidenceReference> evidenceReferences;
  final String? activeTaskId;
  final int omittedUserMessageCount;
  final List<String> diagnostics;
}


/// Freeze nested JSON-compatible session values at the DTO boundary so every
/// caller receives the same immutability guarantee, not only the SQLite builder.
Object _freezeSessionValue(Object? value) {
  if (value == null) {
    throw ArgumentError.value(value, 'value', 'Must not be null');
  }
  if (value is String || value is num || value is bool) return value;
  if (value is Map) {
    final frozen = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(value, 'value', 'Map keys must be strings');
      }
      frozen[key] = _freezeNullableSessionValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(frozen);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeNullableSessionValue));
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_freezeNullableSessionValue));
  }
  throw ArgumentError.value(value, 'value', 'Must be JSON-compatible');
}

Object? _freezeNullableSessionValue(Object? value) =>
    value == null ? null : _freezeSessionValue(value);
