import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Content identity for a deterministic tool result snapshot.
///
/// Both input and result are canonicalized recursively. String payloads remain
/// supported for legacy callers; structured maps/lists are the preferred form.
class AiToolResultSnapshot {
  const AiToolResultSnapshot._();

  static String createId({
    required Map<String, Object?> input,
    required String ruleVersion,
    required Object? resultPayload,
  }) {
    final canonicalPayload = canonicalJson({
      'input': input,
      'ruleVersion': ruleVersion,
      'resultPayload': resultPayload,
    });
    return sha256.convert(utf8.encode(canonicalPayload)).toString();
  }

  /// Stable JSON representation for nested maps, iterables and DateTime values.
  static String canonicalJson(Object? value) => jsonEncode(canonicalize(value));

  /// Hashes the immutable structured snapshot envelope, excluding only its
  /// own digest. This binds provenance, execution state, schema, units,
  /// missing-field declarations, input, result and display summary together.
  static String createStructuredId({
    required Map<String, Object?> snapshot,
  }) {
    final inputValue = snapshot['input'];
    final ruleVersion = snapshot['ruleVersion'];
    if (inputValue is! Map || ruleVersion is! String || ruleVersion.isEmpty) {
      throw ArgumentError(
        'A structured snapshot requires input and a non-empty rule version.',
      );
    }
    final payload = Map<String, Object?>.from(snapshot)
      ..remove('snapshotId');
    return createId(
      input: Map<String, Object?>.from(inputValue),
      ruleVersion: ruleVersion,
      resultPayload: payload,
    );
  }

  /// Public so resolvers can compare a structured result field with the
  /// deterministic engine value using the same canonicalization rules.
  static Object? canonicalize(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (var index = 1; index < entries.length; index++) {
        if (entries[index - 1].key == entries[index].key) {
          throw ArgumentError(
            'Snapshot maps cannot contain keys with the same string identity.',
          );
        }
      }
      return <String, Object?>{
        for (final entry in entries)
          entry.key: canonicalize(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(canonicalize).toList(growable: false);
    }
    if (value is DateTime) return value.toIso8601String();
    return value;
  }
}
