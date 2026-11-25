import 'dart:convert';

import 'session_state_snapshot.dart';

enum AssistantReasoningResponseKind {
  answer,
  clarification,
  actionProposal,
  refusal,
  insufficientEvidence;

  String get wireValue => switch (this) {
        answer => 'ANSWER',
        clarification => 'CLARIFICATION',
        actionProposal => 'ACTION_PROPOSAL',
        refusal => 'REFUSAL',
        insufficientEvidence => 'INSUFFICIENT_EVIDENCE',
      };

  static AssistantReasoningResponseKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// App-owned processing status; the model never sets this field.
enum AssistantReasoningResponseStatus {
  completed,
  insufficientEvidence,
  empty,
  parseFailed,
  unknown;

  String get wireValue => switch (this) {
        completed => 'COMPLETED',
        insufficientEvidence => 'INSUFFICIENT_EVIDENCE',
        empty => 'EMPTY',
        parseFailed => 'PARSE_FAILED',
        unknown => 'UNKNOWN',
      };
}

class AssistantReasoningEvidenceReference {
  const AssistantReasoningEvidenceReference({
    required this.evidenceId,
    required this.sourceId,
    required this.sourceLabel,
    required this.title,
    required this.localBacklink,
    required this.locatorStatus,
    required this.sourceKind,
    required this.sourceVerificationStatus,
    required this.bibliographicLocatorVerified,
  });

  final String evidenceId;
  final String sourceId;
  final String sourceLabel;
  final String title;
  final String localBacklink;
  final String locatorStatus;
  final String sourceKind;
  final String sourceVerificationStatus;
  final bool bibliographicLocatorVerified;

  Map<String, Object?> toJson() => {
        'evidenceId': evidenceId,
        'sourceId': sourceId,
        'sourceLabel': sourceLabel,
        'title': title,
        'localBacklink': localBacklink,
        'locatorStatus': locatorStatus,
        'sourceKind': sourceKind,
        'sourceVerificationStatus': sourceVerificationStatus,
        'bibliographicLocatorVerified': bibliographicLocatorVerified,
      };
}

/// Per-turn reasoning request. Retrieved body text remains in the knowledge
/// context; this object carries a bounded session projection and resolved refs.
class AssistantReasoningRequest {
  AssistantReasoningRequest({
    required this.requestId,
    required this.sessionId,
    required this.userText,
    required this.mode,
    required this.retrievalStatus,
    required this.sessionState,
    required List<AssistantReasoningEvidenceReference> evidence,
    this.allowActionProposal = false,
  }) : evidence = List.unmodifiable(evidence) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Must not be empty');
    }
    if (sessionId <= 0) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Must be positive');
    }
    if (userText.trim().isEmpty) {
      throw ArgumentError.value(userText, 'userText', 'Must not be empty');
    }
    if (mode.trim().isEmpty) {
      throw ArgumentError.value(mode, 'mode', 'Must not be empty');
    }
    if (evidence.length > 64) {
      throw ArgumentError.value(evidence, 'evidence', 'Maximum is 64 references');
    }
    final ids = evidence.map((item) => item.evidenceId).toSet();
    if (ids.length != evidence.length ||
        evidence.any((item) =>
            item.evidenceId.trim().isEmpty || item.sourceId.trim().isEmpty)) {
      throw ArgumentError.value(evidence, 'evidence', 'IDs must be non-empty and unique');
    }
    if (sessionState.sessionId != sessionId) {
      throw ArgumentError.value(
        sessionState.sessionId,
        'sessionState.sessionId',
        'Must match the request session',
      );
    }
  }

  final String requestId;
  final int sessionId;
  final String userText;
  final String mode;
  final String retrievalStatus;
  final SessionStateSnapshot sessionState;
  final List<AssistantReasoningEvidenceReference> evidence;
  final bool allowActionProposal;

  Set<String> get allowedEvidenceIds =>
      Set.unmodifiable(evidence.map((item) => item.evidenceId));

  Map<String, Object?> sessionStateJson() => {
        'revision': sessionState.revision,
        'status': sessionState.status.name.toUpperCase(),
        'activeTaskId': sessionState.activeTaskId,
        'facts': sessionState.facts
            .map((fact) => {
                  'factId': fact.factId,
                  'key': fact.key,
                  'value': fact.value,
                  'provenance': fact.provenance.name.toUpperCase(),
                  'sourceIds': fact.sourceIds,
                })
            .toList(growable: false),
        'evidenceReferences': sessionState.evidenceReferences
            .map((reference) => {
                  'sourceId': reference.sourceId,
                  'sourceVersion': reference.sourceVersion,
                  'evidenceId': reference.evidenceId,
                  'chunkId': reference.chunkId,
                })
            .toList(growable: false),
        'diagnostics': sessionState.diagnostics,
      };

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'requestId': requestId,
        'sessionId': sessionId,
        'userText': userText,
        'mode': mode,
        'retrievalStatus': retrievalStatus,
        'sessionState': sessionStateJson(),
        'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
        'allowActionProposal': allowActionProposal,
      };

  String toPromptInstruction() {
    final evidenceJson = jsonEncode(evidence.map((item) => item.toJson()).toList());
    final memoryJson = jsonEncode(sessionStateJson());
    return '''
【本轮结构化推理协议 v1】
requestId：${requestId}
会话状态快照（仅用于当前请求；provenance 必须保留，不得把模型推断说成用户确认）：${memoryJson}
本轮允许引用的证据清单：${evidenceJson}
检索状态：${retrievalStatus}

必须只输出一个 JSON 对象，不得使用 Markdown、代码围栏、前后解释或额外文本。
JSON 顶层字段：
{
  "schemaVersion": 1,
  "requestId": "${requestId}",
  "responseKind": "ANSWER | CLARIFICATION | ACTION_PROPOSAL | REFUSAL | INSUFFICIENT_EVIDENCE",
  "segments": [{"text": "一段完整陈述", "evidenceIds": ["EV-001"]}],
  "referencedEvidenceIds": ["EV-001"],
  "unknowns": ["尚未确认的信息"],
  "conflicts": ["互相冲突的信息"],
  "actionProposal": null
}
约束：
1. evidenceIds 和 referencedEvidenceIds 只能使用允许引用的证据清单中的 evidenceId；referencedEvidenceIds 必须与所有 segments.evidenceIds 的并集完全一致。
2. 每个 ANSWER 段必须至少包含一个 evidenceId；不得将检索到但未实际支持该段的来源挂为引用。
3. 当没有可用证据时，只能返回 INSUFFICIENT_EVIDENCE、CLARIFICATION 或 REFUSAL，不得用模型参数知识冒充本地资料结论。
4. 不确定项放入 unknowns；相互矛盾的材料放入 conflicts；不得自行消除冲突。
5. 来源是否核验由 App 提供的 sourceVerificationStatus 决定；不得声称自己完成了版本、作者或纸本页码核验。
6. ${allowActionProposal ? '允许提出 ACTION_PROPOSAL，但 App 必须另行校验，模型不得声称动作已执行。' : '本路由禁止 ACTION_PROPOSAL，actionProposal 必须为 null。'}
7. 不得输出 schema 外字段，不得编造 sourceId、evidenceId 或工具执行结果。
''';
  }
}
