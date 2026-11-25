import 'package:nihaisha_app/models/session_state_snapshot.dart';

/// App-owned execution state supplied to the reasoning layer.
///
/// This is a projection of a deterministic execution result. It is not parsed
/// from model output and cannot be used to assert that an unverified action
/// succeeded.
enum ReasoningExecutionStatus { notStarted, succeeded, failed, unknown }

/// Stable identity for one evidence block actually supplied to this request.
///
/// The source ID is an App-owned lookup pointer. It is not a verification or
/// authority claim. The corresponding evidence text is transported separately
/// in the existing bounded knowledge-context section.
class ReasoningEvidenceReference {
  const ReasoningEvidenceReference({
    required this.evidenceId,
    required this.sourceId,
  });

  final String evidenceId;
  final String sourceId;

  Map<String, Object?> toMap() => {
        'evidenceId': evidenceId,
        'sourceId': sourceId,
      };
}

/// Immutable, App-projected result from one deterministic business invocation.
///
/// A SUCCEEDED result must carry the actual arguments, structured output and
/// source IDs validated by the App. UNKNOWN is retained as UNKNOWN; the model
/// must never be allowed to turn it into success or trigger a replay.
class ReasoningExecutionResult {
  ReasoningExecutionResult({
    required this.invocationId,
    required this.capabilityId,
    required this.status,
    Map<String, String> actualArguments = const {},
    Map<String, String> resultValues = const {},
    List<String> sourceIds = const [],
    this.failureCode,
    this.safetyMessage,
  })  : actualArguments = Map.unmodifiable(actualArguments),
        resultValues = Map.unmodifiable(resultValues),
        sourceIds = List.unmodifiable(sourceIds) {
    if (invocationId.trim().isEmpty || capabilityId.trim().isEmpty) {
      throw ArgumentError('REASONING_EXECUTION_ID_REQUIRED');
    }
    if (this.actualArguments.keys.any((key) => key.trim().isEmpty) ||
        this.resultValues.keys.any((key) => key.trim().isEmpty) ||
        this.sourceIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('REASONING_EXECUTION_CONTAINS_EMPTY_ID_OR_KEY');
    }
    if (status == ReasoningExecutionStatus.succeeded &&
        (this.actualArguments.isEmpty ||
            this.resultValues.isEmpty ||
            this.sourceIds.isEmpty)) {
      throw ArgumentError('REASONING_SUCCEEDED_RESULT_INCOMPLETE');
    }
    if (status == ReasoningExecutionStatus.notStarted &&
        (this.resultValues.isNotEmpty || this.sourceIds.isNotEmpty)) {
      throw ArgumentError('REASONING_NOT_STARTED_HAS_RESULT');
    }
    if (status == ReasoningExecutionStatus.succeeded &&
        failureCode != null) {
      throw ArgumentError('REASONING_SUCCEEDED_HAS_FAILURE_CODE');
    }
  }

  final String invocationId;
  final String capabilityId;
  final ReasoningExecutionStatus status;
  final Map<String, String> actualArguments;
  final Map<String, String> resultValues;
  final List<String> sourceIds;
  final String? failureCode;
  final String? safetyMessage;

  Map<String, Object?> toMap() => {
        'invocationId': invocationId,
        'capabilityId': capabilityId,
        'status': _executionStatusName(status),
        'actualArguments': actualArguments,
        'resultValues': resultValues,
        'sourceIds': sourceIds,
        if (failureCode != null) 'failureCode': failureCode,
        if (safetyMessage != null) 'safetyMessage': safetyMessage,
      };
}

/// Complete immutable input contract for one local E4B reasoning turn.
///
/// [userText] is kept byte-for-byte/string-for-string as supplied by the UI;
/// prompt formatting must not replace it with a rewritten query. Session
/// memory, evidence identity and deterministic execution results are separate
/// bounded sections. Evidence bodies remain in the separately assembled
/// knowledge context and are never copied into session memory.
class ReasoningRequest {
  ReasoningRequest({
    required this.requestId,
    required this.sessionId,
    required this.userText,
    required this.mode,
    required this.responseSchemaVersion,
    this.sessionState,
    List<ReasoningEvidenceReference> rankedEvidence = const [],
    List<String> knownEvidenceIds = const [],
    List<ReasoningExecutionResult> executionResults = const [],
  })  : rankedEvidence = List.unmodifiable(rankedEvidence),
        knownEvidenceIds = List.unmodifiable(knownEvidenceIds),
        executionResults = List.unmodifiable(executionResults) {
    if (requestId.trim().isEmpty || requestId != requestId.trim()) {
      throw ArgumentError('REASONING_REQUEST_ID_INVALID');
    }
    if (sessionId <= 0) {
      throw ArgumentError('REASONING_SESSION_ID_INVALID');
    }
    if (userText.trim().isEmpty) {
      throw ArgumentError('REASONING_USER_TEXT_EMPTY');
    }
    if (mode.trim().isEmpty || mode != mode.trim()) {
      throw ArgumentError('REASONING_MODE_INVALID');
    }
    if (responseSchemaVersion != 1) {
      throw ArgumentError('REASONING_RESPONSE_SCHEMA_VERSION_UNSUPPORTED');
    }
    if (sessionState != null && sessionState.sessionId != sessionId) {
      throw ArgumentError('REASONING_SESSION_STATE_SESSION_ID_MISMATCH');
    }

    final knownIds = this.knownEvidenceIds.toSet();
    if (knownIds.length != this.knownEvidenceIds.length ||
        this.knownEvidenceIds.any((id) => id.trim().isEmpty || id != id.trim())) {
      throw ArgumentError('REASONING_KNOWN_EVIDENCE_IDS_INVALID');
    }
    if (this.rankedEvidence.any((item) =>
        item.evidenceId.trim().isEmpty ||
        item.evidenceId != item.evidenceId.trim() ||
        item.sourceId.trim().isEmpty ||
        item.sourceId != item.sourceId.trim())) {
      throw ArgumentError('REASONING_RANKED_EVIDENCE_REFERENCE_INVALID');
    }
    final rankedIds = this.rankedEvidence.map((item) => item.evidenceId).toSet();
    if (rankedIds.length != this.rankedEvidence.length ||
        !knownIds.containsAll(rankedIds)) {
      throw ArgumentError('REASONING_RANKED_EVIDENCE_NOT_IN_KNOWN_CANDIDATES');
    }
    final invocationIds =
        this.executionResults.map((item) => item.invocationId).toSet();
    if (invocationIds.length != this.executionResults.length) {
      throw ArgumentError('REASONING_EXECUTION_INVOCATION_ID_DUPLICATE');
    }
  }

  final String requestId;
  final int sessionId;
  final String userText;
  final String mode;
  final SessionStateSnapshot? sessionState;
  final List<ReasoningEvidenceReference> rankedEvidence;
  final List<String> knownEvidenceIds;
  final List<ReasoningExecutionResult> executionResults;
  final int responseSchemaVersion;

  List<String> get rankedEvidenceIds => List.unmodifiable(
        rankedEvidence.map((item) => item.evidenceId),
      );

  /// Complete DTO projection for storage/diagnostics or a future wire adapter.
  ///
  /// Do not persist this as Native recovery transcript: session state and
  /// retrieved evidence are ephemeral request inputs.
  Map<String, Object?> toMap() => {
        'requestId': requestId,
        'sessionId': sessionId,
        'userText': userText,
        'mode': mode,
        'responseSchemaVersion': responseSchemaVersion,
        'sessionState': sessionState == null
            ? null
            : _sessionStateToMap(sessionState!),
        'rankedEvidence': rankedEvidence.map((item) => item.toMap()).toList(),
        'knownEvidenceIds': knownEvidenceIds,
        'executionResults':
            executionResults.map((item) => item.toMap()).toList(),
      };
}

Map<String, Object?> _sessionStateToMap(SessionStateSnapshot snapshot) {
  final canExposeFacts = snapshot.status != SessionStateStatus.unknown &&
      snapshot.status != SessionStateStatus.sessionMismatch;
  return {
    'sessionId': snapshot.sessionId,
    'revision': snapshot.revision,
    'status': switch (snapshot.status) {
      SessionStateStatus.restored => 'RESTORED',
      SessionStateStatus.partial => 'PARTIAL',
      SessionStateStatus.sessionMismatch => 'SESSION_MISMATCH',
      SessionStateStatus.unknown => 'UNKNOWN',
    },
    // Match SessionStateSnapshotPromptFormatter's fail-closed behavior:
    // unknown/mismatched memory may not leak attached facts through toMap().
    'facts': canExposeFacts
        ? snapshot.facts
            .map(
              (fact) => {
                'factId': fact.factId,
                'key': fact.key,
                'value': fact.value,
                'provenance': switch (fact.provenance) {
                  SessionFactProvenance.userOriginal => 'USER_ORIGINAL',
                  SessionFactProvenance.userConfirmed => 'USER_CONFIRMED',
                  SessionFactProvenance.modelInferred => 'MODEL_INFERRED',
                  SessionFactProvenance.appResult => 'APP_RESULT',
                  SessionFactProvenance.sourceReference => 'SOURCE_REFERENCE',
                },
                'sourceIds': fact.sourceIds,
              },
            )
            .toList()
        : const [],
    'evidenceReferences': canExposeFacts
        ? snapshot.evidenceReferences
            .map(
              (reference) => {
                'sourceId': reference.sourceId,
                'sourceVersion': reference.sourceVersion,
                'evidenceId': reference.evidenceId,
                'chunkId': reference.chunkId,
              },
            )
            .toList()
        : const [],
    if (canExposeFacts && snapshot.activeTaskId != null)
      'activeTaskId': snapshot.activeTaskId,
    'omittedUserMessageCount': snapshot.omittedUserMessageCount,
    'diagnostics': snapshot.diagnostics,
  };
}

String _executionStatusName(ReasoningExecutionStatus status) =>
    switch (status) {
      ReasoningExecutionStatus.notStarted => 'NOT_STARTED',
      ReasoningExecutionStatus.succeeded => 'SUCCEEDED',
      ReasoningExecutionStatus.failed => 'FAILED',
      ReasoningExecutionStatus.unknown => 'UNKNOWN',
    };
