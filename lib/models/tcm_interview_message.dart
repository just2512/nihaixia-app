import 'dart:convert';

/// A structured turn emitted by the deterministic TCM interview workflow.
///
/// The message is deliberately independent from Flutter widgets so the same
/// payload can be rendered in the assistant timeline and persisted as message
/// metadata. Diagnostic decisions remain owned by DiagnosticEngine.
enum TcmInterviewMessageType {
  question,
  choice,
  answer,
  evidence,
  diagnosisResult,
  error,
}

class TcmInterviewMessage {
  const TcmInterviewMessage({
    required this.id,
    required this.taskId,
    required this.type,
    required this.content,
    required this.createdAt,
    this.promptId,
    this.options = const [],
    this.selectedAnswer,
    this.source,
  });

  final String id;
  final String taskId;
  final TcmInterviewMessageType type;
  final String content;
  final DateTime createdAt;
  final String? promptId;
  final List<String> options;
  final String? selectedAnswer;
  final String? source;

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'taskId': taskId,
        'type': type.name,
        'content': content,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (promptId != null) 'promptId': promptId,
        'options': List<String>.unmodifiable(options),
        if (selectedAnswer != null) 'selectedAnswer': selectedAnswer,
        if (source != null) 'source': source,
      };

  String encode() => jsonEncode(toJson());

  factory TcmInterviewMessage.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw FormatException(
        'Unsupported TCM interview message schema: ${json['schemaVersion']}',
      );
    }
    final id = json['id'];
    final taskId = json['taskId'];
    final content = json['content'];
    final typeName = json['type'];
    final createdAt = json['createdAt'];
    final options = json['options'];
    if (id is! String ||
        id.trim().isEmpty ||
        taskId is! String ||
        taskId.trim().isEmpty ||
        content is! String ||
        typeName is! String ||
        createdAt is! String ||
        options is! List ||
        options.any((item) => item is! String)) {
      throw const FormatException('Invalid TCM interview message payload');
    }
    final type = TcmInterviewMessageType.values
        .where((item) => item.name == typeName);
    if (type.isEmpty) {
      throw FormatException('Unknown TCM interview message type: $typeName');
    }
    final promptId = json['promptId'];
    final selectedAnswer = json['selectedAnswer'];
    final source = json['source'];
    if ((promptId != null && promptId is! String) ||
        (selectedAnswer != null && selectedAnswer is! String) ||
        (source != null && source is! String)) {
      throw const FormatException('Invalid optional TCM interview message field');
    }
    return TcmInterviewMessage(
      id: id,
      taskId: taskId,
      type: type.first,
      content: content,
      createdAt: DateTime.parse(createdAt).toUtc(),
      promptId: promptId as String?,
      options: List<String>.unmodifiable(options.cast<String>()),
      selectedAnswer: selectedAnswer as String?,
      source: source as String?,
    );
  }

  factory TcmInterviewMessage.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('TCM interview message must be a JSON object');
    }
    return TcmInterviewMessage.fromJson(
      Map<String, Object?>.from(decoded),
    );
  }
}
