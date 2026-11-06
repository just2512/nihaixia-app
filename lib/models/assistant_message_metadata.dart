import 'dart:convert';

class AssistantMessageMetadata {
  const AssistantMessageMetadata({this.mode, this.selectedMode, this.toolId, this.toolChoicePending = false, this.replayable = true, this.attachmentType, this.tcmTaskId, this.toolStatus, this.sourceIds = const []});
  final String? mode;
  final String? selectedMode;
  final String? toolId;
  final bool toolChoicePending;
  final bool replayable;
  final String? attachmentType;
  final String? tcmTaskId;
  final String? toolStatus;
  final List<String> sourceIds;
  Map<String, dynamic> toJson() => {'schemaVersion': 1, if (mode != null) 'mode': mode, if (selectedMode != null) 'selectedMode': selectedMode, if (toolId != null) 'toolId': toolId, 'toolChoicePending': toolChoicePending, 'replayable': replayable, if (attachmentType != null) 'attachmentType': attachmentType, if (tcmTaskId != null) 'tcmTaskId': tcmTaskId, if (toolStatus != null) 'toolStatus': toolStatus, if (sourceIds.isNotEmpty) 'sourceIds': sourceIds};
  String encode() => jsonEncode(toJson());
  factory AssistantMessageMetadata.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['schemaVersion'] == 1) {
        String? read(String key) => decoded[key] is String ? decoded[key] as String : null;
        return AssistantMessageMetadata(mode: read('mode'), selectedMode: read('selectedMode'), toolId: read('toolId'), toolChoicePending: decoded['toolChoicePending'] == true, replayable: decoded['replayable'] != false, attachmentType: read('attachmentType'), tcmTaskId: read('tcmTaskId'), toolStatus: read('toolStatus'), sourceIds: decoded['sourceIds'] is List ? (decoded['sourceIds'] as List).whereType<String>().toList() : const []);
      }
    } catch (_) {}
    final legacy = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) legacy[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return AssistantMessageMetadata(mode: legacy['mode'], selectedMode: legacy['selectedMode'], toolId: legacy['tool'], toolChoicePending: legacy['tool_choice'] == 'true', replayable: legacy['replayable'] != 'false', attachmentType: legacy['attachment'], tcmTaskId: legacy['tcm_task']);
  }
}
