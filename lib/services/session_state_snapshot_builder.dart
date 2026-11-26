import '../models/assistant_message_metadata.dart';
import '../models/diagnosis_result_codec.dart';
import '../models/session_state_snapshot.dart';
import '../models/tcm_interview_task_state.dart';

/// Pure, read-only projection from the existing per-session SQLite records.
///
/// The caller must pass the owner ID used for each keyed read. Every returned
/// message row is independently checked against the requested ID before any
/// fact/reference is admitted. A mismatch invalidates the entire snapshot.
class SessionStateSnapshotBuilder {
  static const int maxUserOriginalMessages = 8;
  static const int maxUserMessageCharacters = 1200;
  static const int maxEvidenceReferences = 64;
  static const int maxStructuredFacts = 64;

  static SessionStateSnapshot build({
    required int sessionId,
    required List<Map<String, Object?>> messages,
    TcmInterviewTaskState? taskState,
    int? taskOwnerSessionId,
  }) {
    if (sessionId <= 0) {
      return _mismatch(sessionId, 'INVALID_SESSION_ID');
    }
    if (taskState != null && taskOwnerSessionId != sessionId) {
      return _mismatch(sessionId, 'TASK_SESSION_ID_MISMATCH');
    }

    final validMessages = <_SessionMessage>[];
    var partial = false;
    var omittedUserMessageCount = 0;
    var omittedEvidenceReferenceCount = 0;
    var omittedFactCount = 0;
    var maxMessageId = 0;

    for (final row in messages) {
      final owner = row['conversation_id'];
      if (owner is! int) {
        partial = true;
        continue;
      }
      if (owner != sessionId) {
        return _mismatch(sessionId, 'MESSAGE_SESSION_ID_MISMATCH');
      }

      final messageId = row['id'];
      final role = row['role'];
      final content = row['content'];
      if (messageId is! int ||
          messageId <= 0 ||
          role is! String ||
          content is! String) {
        partial = true;
        continue;
      }
      if (messageId > maxMessageId) maxMessageId = messageId;
      validMessages.add(
        _SessionMessage(
          id: messageId,
          role: role.trim().toLowerCase(),
          content: content,
          metadata: row['metadata'] is String
              ? row['metadata'] as String
              : null,
        ),
      );
    }

    // Database callers may provide rows in either direction. Normalize here so
    // the bounded tail and evidence-reference order do not depend on query order.
    validMessages.sort((left, right) => left.id.compareTo(right.id));

    final userMessages = validMessages
        .where((message) => message.role == 'user' && message.content.trim().isNotEmpty)
        .toList(growable: false);
    final eligibleUserMessages = <_SessionMessage>[];
    for (final message in userMessages) {
      if (message.content.length > maxUserMessageCharacters) {
        partial = true;
        omittedUserMessageCount++;
        continue;
      }
      eligibleUserMessages.add(message);
    }
    if (eligibleUserMessages.length > maxUserOriginalMessages) {
      omittedUserMessageCount +=
          eligibleUserMessages.length - maxUserOriginalMessages;
      partial = true;
    }
    final boundedUserMessages = eligibleUserMessages.length <= maxUserOriginalMessages
        ? eligibleUserMessages
        : eligibleUserMessages.sublist(
            eligibleUserMessages.length - maxUserOriginalMessages,
          );

    final facts = <SessionStateFact>[];
    for (final message in boundedUserMessages) {
      facts.add(
        SessionStateFact(
          factId: 'message:${message.id}',
          key: 'user_original',
          value: message.content,
          provenance: SessionFactProvenance.userOriginal,
          sourceIds: ['message:${message.id}'],
        ),
      );
    }

    final evidenceReferences = <SessionEvidenceReference>[];
    final seenReferenceKeys = <String>{};
    for (final message in validMessages) {
      // Hidden tool-role invocation ledger events are execution state, not
      // user/assistant memory or retrieval provenance. They are consumed only
      // by AssistantToolInvocationLedger and must never enter Native prompts.
      if (message.role != 'user' && message.role != 'assistant') continue;
      final rawMetadata = message.metadata;
      if (rawMetadata == null || rawMetadata.trim().isEmpty) continue;
      final metadata = AssistantMessageMetadata.decode(rawMetadata);
      for (final sourceId in metadata.sourceIds) {
        _addReference(
          evidenceReferences,
          seenReferenceKeys,
          sourceId: sourceId,
        );
      }
      final contextSourceId = metadata.contextRef['sourceId'];
      if (contextSourceId is String && contextSourceId.trim().isNotEmpty) {
        _addReference(
          evidenceReferences,
          seenReferenceKeys,
          sourceId: contextSourceId,
          evidenceId: _stringValue(metadata.contextRef['anchorId']),
          chunkId: _stringValue(metadata.contextRef['chunkId']),
        );
      }
      for (final step in metadata.toolPlanSteps) {
        for (final sourceId in step.sourceIds) {
          _addReference(
            evidenceReferences,
            seenReferenceKeys,
            sourceId: sourceId,
          );
        }
      }
    }
    if (evidenceReferences.length > maxEvidenceReferences) {
      omittedEvidenceReferenceCount =
          evidenceReferences.length - maxEvidenceReferences;
      evidenceReferences.removeRange(
        maxEvidenceReferences,
        evidenceReferences.length,
      );
      partial = true;
    }

    String? activeTaskId;
    if (taskState != null) {
      activeTaskId = taskState.taskId;
      final taskPrefix = 'task:${taskState.taskId}';

      // These fields are produced by the deterministic TCM adapter after
      // direct UI selection or explicit user confirmation. No assistant
      // free-text statement is promoted into a structured fact.
      for (final symptom in taskState.snapshot.selectedSymptoms) {
        _addFact(
          facts,
          factId: '$taskPrefix:selected-symptom:$symptom',
          key: 'selected_symptom',
          value: symptom,
          provenance: SessionFactProvenance.userConfirmed,
        );
      }
      for (final entry in taskState.snapshot.answers.entries) {
        if (entry.value == null) continue;
        _addFact(
          facts,
          factId: '$taskPrefix:answer:${entry.key}',
          key: 'interview_answer:${entry.key}',
          value: entry.value,
          provenance: SessionFactProvenance.userConfirmed,
        );
      }
      for (final entry in taskState.snapshot.qAnswers.entries) {
        _addFact(
          facts,
          factId: '$taskPrefix:q-answer:${entry.key}',
          key: 'rule_question_answer:${entry.key}',
          value: entry.value,
          provenance: SessionFactProvenance.userConfirmed,
        );
      }
      for (final entry in taskState.pendingConfirmedTenAnswers.entries) {
        _addFact(
          facts,
          factId: '$taskPrefix:confirmed-pending:${entry.key}',
          key: 'confirmed_pending_answer:${entry.key}',
          value: entry.value,
          provenance: SessionFactProvenance.userConfirmed,
        );
      }
      _addOptionalFact(
        facts,
        taskPrefix: taskPrefix,
        key: 'tongue_coating',
        value: taskState.snapshot.tongueCoating,
      );
      _addOptionalFact(
        facts,
        taskPrefix: taskPrefix,
        key: 'tongue_shape',
        value: taskState.snapshot.tongueShape,
      );
      _addOptionalFact(
        facts,
        taskPrefix: taskPrefix,
        key: 'pulse_type',
        value: taskState.snapshot.pulseType,
      );
      _addOptionalFact(
        facts,
        taskPrefix: taskPrefix,
        key: 'pulse_type_secondary',
        value: taskState.snapshot.pulseTypeSecondary,
      );
      _addOptionalFact(
        facts,
        taskPrefix: taskPrefix,
        key: 'gender',
        value: taskState.snapshot.gender,
      );

      final diagnosis = taskState.completedDiagnosis;
      if (diagnosis != null) {
        _addFact(
          facts,
          factId: '$taskPrefix:completed-diagnosis',
          key: 'completed_diagnosis',
          value: DiagnosisResultCodec.toJson(diagnosis),
          provenance: SessionFactProvenance.appResult,
          sourceIds: [taskState.taskId],
        );
      }
    }

    if (facts.length > maxStructuredFacts) {
      omittedFactCount = facts.length - maxStructuredFacts;
      facts.removeRange(maxStructuredFacts, facts.length);
      partial = true;
    }

    final hasData =
        facts.isNotEmpty || evidenceReferences.isNotEmpty || taskState != null;
    final status = !hasData
        ? (partial ? SessionStateStatus.partial : SessionStateStatus.unknown)
        : partial
            ? SessionStateStatus.partial
            : SessionStateStatus.restored;

    final updatedAt = taskState?.updatedAt?.toUtc().toIso8601String() ?? 'MISSING';
    return SessionStateSnapshot(
      sessionId: sessionId,
      revision: 'message-id:$maxMessageId|task-updated-at:$updatedAt',
      status: status,
      facts: facts,
      evidenceReferences: evidenceReferences,
      activeTaskId: activeTaskId,
      omittedUserMessageCount: omittedUserMessageCount,
      diagnostics: [
        if (partial) 'SESSION_STATE_PARTIAL',
        if (omittedUserMessageCount > 0)
          'USER_ORIGINAL_MESSAGES_OMITTED:$omittedUserMessageCount',
        if (omittedFactCount > 0) 'SESSION_FACTS_OMITTED:$omittedFactCount',
        if (omittedEvidenceReferenceCount > 0)
          'SESSION_EVIDENCE_REFERENCES_OMITTED:$omittedEvidenceReferenceCount',
        if (taskState == null) 'TCM_TASK_STATE_NOT_PRESENT',
      ],
    );
  }

  static SessionStateSnapshot _mismatch(int sessionId, String diagnostic) =>
      SessionStateSnapshot(
        sessionId: sessionId,
        revision: 'SESSION_MISMATCH',
        status: SessionStateStatus.sessionMismatch,
        facts: const [],
        evidenceReferences: const [],
        diagnostics: [diagnostic],
      );

  static void _addOptionalFact(
    List<SessionStateFact> facts, {
    required String taskPrefix,
    required String key,
    required String? value,
  }) {
    if (value == null || value.trim().isEmpty) return;
    _addFact(
      facts,
      factId: '$taskPrefix:$key',
      key: key,
      value: value,
      provenance: SessionFactProvenance.userConfirmed,
    );
  }

  static void _addFact(
    List<SessionStateFact> facts, {
    required String factId,
    required String key,
    required Object value,
    required SessionFactProvenance provenance,
    List<String> sourceIds = const [],
  }) {
    facts.add(
      SessionStateFact(
        factId: factId,
        key: key,
        value: value,
        provenance: provenance,
        sourceIds: sourceIds,
      ),
    );
  }

  static String? _stringValue(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static void _addReference(
    List<SessionEvidenceReference> references,
    Set<String> seenKeys, {
    required String sourceId,
    String? evidenceId,
    String? chunkId,
  }) {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) return;
    final normalizedEvidenceId = _nonEmpty(evidenceId);
    final normalizedChunkId = _nonEmpty(chunkId);
    final key = '$normalizedSourceId|${normalizedEvidenceId ?? ''}|'
        '${normalizedChunkId ?? ''}';
    if (!seenKeys.add(key)) return;
    references.add(
      SessionEvidenceReference(
        sourceId: normalizedSourceId,
        sourceVersion: 'UNKNOWN',
        evidenceId: normalizedEvidenceId,
        chunkId: normalizedChunkId,
      ),
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _SessionMessage {
  const _SessionMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.metadata,
  });

  final int id;
  final String role;
  final String content;
  final String? metadata;
}
