import 'dart:convert';

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
  });

  final String? mode;
  final String? selectedMode;
  final String? toolId;
  final bool toolChoicePending;
  final bool replayable;
  final String? attachmentType;
  final String? tcmTaskId;
  final String? toolStatus;
  final List<String> sourceIds;
  final Map<String, String> toolArguments;

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
      };

  String encode() => jsonEncode(toJson());

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
