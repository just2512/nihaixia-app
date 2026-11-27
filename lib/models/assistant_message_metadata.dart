import 'dart:convert';

/// Per-step execution provenance stored with an AI multi-tool turn.
class AssistantToolPlanStepMetadata {
  const AssistantToolPlanStepMetadata({
    required this.toolId,
    required this.capabilityId,
    required this.title,
    required this.status,
    this.arguments = const {},
    this.sourceIds = const [],
  });

  final String toolId;
  final String capabilityId;
  final String title;
  final String status;
  final Map<String, String> arguments;
  final List<String> sourceIds;

  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'capabilityId': capabilityId,
        'title': title,
        'status': status,
        'arguments': arguments,
        'sourceIds': sourceIds,
      };

  static AssistantToolPlanStepMetadata? tryDecode(Object? raw) {
    if (raw is! Map) return null;
    final toolId = raw['toolId'];
    final capabilityId = raw['capabilityId'];
    final title = raw['title'];
    final status = raw['status'];
    if (toolId is! String ||
        capabilityId is! String ||
        title is! String ||
        status is! String ||
        toolId.trim().isEmpty ||
        capabilityId.trim().isEmpty ||
        title.trim().isEmpty ||
        status.trim().isEmpty) {
      return null;
    }
    final rawArguments = raw['arguments'];
    final arguments = <String, String>{};
    if (rawArguments is Map) {
      for (final entry in rawArguments.entries) {
        if (entry.key is String && entry.value is String) {
          arguments[entry.key as String] = entry.value as String;
        }
      }
    }
    final rawSources = raw['sourceIds'];
    final sourceIds = rawSources is List
        ? rawSources.whereType<String>().toList(growable: false)
        : const <String>[];
    return AssistantToolPlanStepMetadata(
      toolId: toolId,
      capabilityId: capabilityId,
      title: title,
      status: status,
      arguments: Map<String, String>.unmodifiable(arguments),
      sourceIds: List<String>.unmodifiable(sourceIds),
    );
  }
}

/// Typed, versioned metadata persisted with every assistant conversation message.
/// Decoder remains backward-compatible with the historical semicolon format.
class AssistantMessageMetadata {
  const AssistantMessageMetadata({
    this.mode,
    this.selectedMode,
    this.toolId,
    this.toolChoicePending = false,
    this.replayable = true,
    this.attachmentType,
    this.tcmTaskId,
    this.toolStatus,
    this.sourceIds = const [],
    this.toolArguments = const {},
    this.knowledgeStatus,
    this.traceId,
    this.reasoningRequestId,
    this.invocationOrigin,
    this.contextRef = const {},
    this.toolPlanSteps = const [],
  });

  final String? mode;
  final String? selectedMode;
  final String? toolId;
  final bool toolChoicePending;
  final bool replayable;
  final String? attachmentType;
  final String? tcmTaskId;
  final String? toolStatus;
  /// Per-turn provenance returned by App retrieval or deterministic execution.
  /// These IDs do not assert that the model used or cited each retrieved item.
  final List<String> sourceIds;
  final Map<String, String> toolArguments;
  final String? knowledgeStatus;
  /// Opaque per-turn correlation ID; never user content.
  final String? traceId;
  /// Durable identity linking transcript rows to a structured reasoning turn.
  final String? reasoningRequestId;
  /// Explicit source of a pending tool plan; null means MISSING, never inferred.
  final String? invocationOrigin;
  /// Immutable contextual anchor carried by every message in the anchored turn.
  final Map<String, String> contextRef;
  final List<AssistantToolPlanStepMetadata> toolPlanSteps;

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        if (mode != null) 'mode': mode,
        if (selectedMode != null) 'selectedMode': selectedMode,
        if (toolId != null) 'toolId': toolId,
        'toolChoicePending': toolChoicePending,
        'replayable': replayable,
        if (attachmentType != null) 'attachmentType': attachmentType,
        if (tcmTaskId != null) 'tcmTaskId': tcmTaskId,
        if (toolStatus != null) 'toolStatus': toolStatus,
        if (sourceIds.isNotEmpty) 'sourceIds': sourceIds,
        if (toolArguments.isNotEmpty) 'toolArguments': toolArguments,
        if (knowledgeStatus != null) 'knowledgeStatus': knowledgeStatus,
        if (traceId != null) 'trace_id': traceId,
        if (reasoningRequestId != null) 'reasoningRequestId': reasoningRequestId,
        if (invocationOrigin != null) 'invocationOrigin': invocationOrigin,
        if (contextRef.isNotEmpty) 'contextRef': contextRef,
        if (toolPlanSteps.isNotEmpty)
          'toolPlanSteps': toolPlanSteps.map((step) => step.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  /// Returns whether a persisted message may be promoted into SessionState
  /// memory. This is intentionally stricter than [decode], whose general
  /// fallback remains backward-compatible for UI/history rendering.
  ///
  /// Missing metadata remains compatible with historical rows. Recognized
  /// schema v1 and known legacy semicolon metadata are supported; unknown
  /// schema versions and malformed/unrecognized payloads fail closed.
  static bool isReplayableForSessionMemory(String? raw) {
    if (raw == null || raw.trim().isEmpty) return true;
    final normalized = raw.trim();

    Object? decoded;
    try {
      decoded = jsonDecode(normalized);
    } on FormatException {
      if (normalized.startsWith('{') || normalized.startsWith('[')) {
        return false;
      }
      return _isReplayableLegacyMetadata(normalized);
    } catch (_) {
      return false;
    }

    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      return false;
    }
    if (!decoded.containsKey('replayable')) return true;
    return decoded['replayable'] == true;
  }

  static bool _isReplayableLegacyMetadata(String raw) {
    const recognizedKeys = {
      'mode',
      'selectedMode',
      'tool',
      'tool_choice',
      'replayable',
      'attachment',
      'tcm_task',
    };
    final legacy = <String, String>{};
    for (final part in raw.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) return false;
      final key = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (!recognizedKeys.contains(key) || legacy.containsKey(key)) {
        return false;
      }
      if (key == 'replayable' && value != 'true' && value != 'false') {
        return false;
      }
      legacy[key] = value;
    }
    if (legacy.isEmpty) return false;
    return legacy['replayable'] != 'false';
  }

  factory AssistantMessageMetadata.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['schemaVersion'] == 1) {
        String? readString(String key) =>
            decoded[key] is String ? decoded[key] as String : null;
        return AssistantMessageMetadata(
          mode: readString('mode'),
          selectedMode: readString('selectedMode'),
          toolId: readString('toolId'),
          toolChoicePending: decoded['toolChoicePending'] == true,
          replayable: decoded['replayable'] != false,
          attachmentType: readString('attachmentType'),
          tcmTaskId: readString('tcmTaskId'),
          toolStatus: readString('toolStatus'),
          sourceIds: decoded['sourceIds'] is List
              ? (decoded['sourceIds'] as List).whereType<String>().toList()
              : const [],
          knowledgeStatus: readString('knowledgeStatus'),
          traceId: readString('trace_id'),
          reasoningRequestId: readString('reasoningRequestId'),
          invocationOrigin: readString('invocationOrigin'),
          toolPlanSteps: decoded['toolPlanSteps'] is List
              ? (decoded['toolPlanSteps'] as List)
                  .map(AssistantToolPlanStepMetadata.tryDecode)
                  .whereType<AssistantToolPlanStepMetadata>()
                  .toList(growable: false)
              : const [],
          contextRef: decoded['contextRef'] is Map
              ? Map<String, String>.fromEntries(
                  (decoded['contextRef'] as Map).entries.where(
                    (entry) => entry.key is String && entry.value is String,
                  ).map((entry) => MapEntry(
                        entry.key as String,
                        entry.value as String,
                      )),
                )
              : const {},
          toolArguments: decoded['toolArguments'] is Map
              ? Map<String, String>.fromEntries(
                  (decoded['toolArguments'] as Map).entries.where(
                    (entry) => entry.key is String && entry.value is String,
                  ).map((entry) => MapEntry(
                        entry.key as String,
                        entry.value as String,
                      )),
                )
              : const {},
        );
      }
    } catch (_) {
      // Continue with the legacy decoder below.
    }

    final legacy = <String, String>{};
    for (final part in raw.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      legacy[part.substring(0, separator).trim()] =
          part.substring(separator + 1).trim();
    }
    return AssistantMessageMetadata(
      mode: legacy['mode'],
      selectedMode: legacy['selectedMode'],
      toolId: legacy['tool'],
      toolChoicePending: legacy['tool_choice'] == 'true',
      replayable: legacy['replayable'] != 'false',
      attachmentType: legacy['attachment'],
      tcmTaskId: legacy['tcm_task'],
    );
  }
}
