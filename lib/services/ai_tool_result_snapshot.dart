import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Content identity for a deterministic tool result snapshot.
///
/// The digest includes the exact input values supplied to the engine, the
/// engine/formatter rule version, and the complete normalized result payload.
class AiToolResultSnapshot {
  const AiToolResultSnapshot._();

  static String createId({
    required Map<String, Object?> input,
    required String ruleVersion,
    required String resultPayload,
  }) {
    final canonicalInput = _canonicalize(input) as Map<String, Object?>;
    final canonicalPayload = jsonEncode({
      'input': canonicalInput,
      'ruleVersion': ruleVersion,
      'resultPayload': resultPayload,
    });
    return sha256.convert(utf8.encode(canonicalPayload)).toString();
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is DateTime) return value.toIso8601String();
    return value;
  }
}
