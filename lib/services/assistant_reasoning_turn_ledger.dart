import 'dart:convert';

import '../data/assistant_conversation_store.dart';

enum AssistantReasoningTurnStatus { pending, finalized, rejected, unknown }

enum AssistantReasoningTurnStartStatus {
  started,
  alreadyPending,
  alreadyTerminal,
  conflictingRequest,
}

enum AssistantReasoningTurnTerminalWriteStatus {
  recorded,
  alreadyRecorded,
  missingRequest,
  conflictingTerminal,
}

class AssistantReasoningTurnRecord {
  const AssistantReasoningTurnRecord({
    required this.conversationId,
    required this.requestId,
    required this.mode,
    required this.userText,
    required this.createdAt,
    required this.status,
    this.answerText,
    this.sourceIds = const [],
    this.failureCode,
    this.interrupted = false,
  });

  final int conversationId;
  final String requestId;
  final String mode;
  final String userText;
  final String createdAt;
  final AssistantReasoningTurnStatus status;
  final String? answerText;
  final List<String> sourceIds;
  final String? failureCode;
  final bool interrupted;
}

/// Durable request-state boundary for structured Native reasoning turns.
///
/// The ledger reuses hidden `role=tool` rows and the existing per-conversation
/// partial unique index. It is deliberately separate from Native's in-memory
/// completion acknowledgement ledger: a process restart can recover an
/// unresolved request as UNKNOWN without ever replaying model inference.
class AssistantReasoningTurnLedger {
  const AssistantReasoningTurnLedger(this._store);

  final AssistantConversationStore _store;

  static const String _schema = 'assistant-reasoning-turn-v1';
  static const int _maxUserTextCharacters = 12_000;
  static const int _maxAnswerCharacters = 12_000;

  Future<AssistantReasoningTurnStartStatus> begin({
    required int conversationId,
    required String requestId,
    required String mode,
    required String userText,
  }) async {
    _validateIdentity(conversationId, requestId);
    final normalizedMode = mode.trim();
    final normalizedText = userText.trim();
    if (normalizedMode.isEmpty || normalizedMode != mode ||
        !const {'automatic', 'consultation', 'learning', 'metaphysics'}
            .contains(normalizedMode)) {
      throw ArgumentError.value(mode, 'mode', 'REASONING_TURN_MODE_INVALID');
    }
    if (normalizedText.isEmpty || normalizedText.length > _maxUserTextCharacters) {
      throw ArgumentError.value(userText, 'userText', 'REASONING_TURN_USER_TEXT_INVALID');
    }

    final current = await _read(conversationId, requestId);
    if (current != null) {
      if (current.mode != normalizedMode || current.userText != normalizedText) {
        return AssistantReasoningTurnStartStatus.conflictingRequest;
      }
      return current.status == AssistantReasoningTurnStatus.pending
          ? AssistantReasoningTurnStartStatus.alreadyPending
          : AssistantReasoningTurnStartStatus.alreadyTerminal;
    }

    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = <String, Object?>{
      'schema': _schema,
      'kind': 'PENDING',
      'conversationId': conversationId,
      'requestId': requestId,
      'mode': normalizedMode,
      'userText': normalizedText,
      'createdAt': createdAt,
    };
    try {
      await _store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'tool',
        content: 'REASONING_TURN_PENDING',
        metadata: jsonEncode(payload),
        invocationKey: _pendingKey(requestId),
      );
      return AssistantReasoningTurnStartStatus.started;
    } catch (_) {
      final raced = await _read(conversationId, requestId);
      if (raced != null) {
        if (raced.mode != normalizedMode || raced.userText != normalizedText) {
          return AssistantReasoningTurnStartStatus.conflictingRequest;
        }
        return raced.status == AssistantReasoningTurnStatus.pending
            ? AssistantReasoningTurnStartStatus.alreadyPending
            : AssistantReasoningTurnStartStatus.alreadyTerminal;
      }
      rethrow;
    }
  }

  Future<AssistantReasoningTurnTerminalWriteStatus> recordTerminal({
    required int conversationId,
    required String requestId,
    required AssistantReasoningTurnStatus status,
    String? answerText,
    List<String> sourceIds = const [],
    String? failureCode,
  }) async {
    _validateIdentity(conversationId, requestId);
    if (status == AssistantReasoningTurnStatus.pending) {
      throw ArgumentError('REASONING_TURN_TERMINAL_STATUS_REQUIRED');
    }
    final current = await _read(conversationId, requestId);
    if (current == null) {
      return AssistantReasoningTurnTerminalWriteStatus.missingRequest;
    }
    _validateTerminalPayload(
      status: status,
      answerText: answerText,
      sourceIds: sourceIds,
      failureCode: failureCode,
    );
    if (current.status != AssistantReasoningTurnStatus.pending) {
      return _sameTerminal(
        current,
        status: status,
        answerText: answerText,
        sourceIds: sourceIds,
        failureCode: failureCode,
      )
          ? AssistantReasoningTurnTerminalWriteStatus.alreadyRecorded
          : AssistantReasoningTurnTerminalWriteStatus.conflictingTerminal;
    }

    final payload = <String, Object?>{
      'schema': _schema,
      'kind': 'TERMINAL',
      'conversationId': conversationId,
      'requestId': requestId,
      'mode': current.mode,
      'userText': current.userText,
      'status': status.name.toUpperCase(),
      if (answerText != null) 'answerText': answerText,
      if (sourceIds.isNotEmpty) 'sourceIds': sourceIds,
      if (failureCode != null) 'failureCode': failureCode,
      'interrupted': status == AssistantReasoningTurnStatus.unknown,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'tool',
        content: 'REASONING_TURN_${status.name.toUpperCase()}',
        metadata: jsonEncode(payload),
        invocationKey: _terminalKey(requestId),
      );
      return AssistantReasoningTurnTerminalWriteStatus.recorded;
    } catch (_) {
      final raced = await _read(conversationId, requestId);
      if (raced == null) rethrow;
      return _sameTerminal(
        raced,
        status: status,
        answerText: answerText,
        sourceIds: sourceIds,
        failureCode: failureCode,
      )
          ? AssistantReasoningTurnTerminalWriteStatus.alreadyRecorded
          : AssistantReasoningTurnTerminalWriteStatus.conflictingTerminal;
    }
  }

  /// Call only while opening/restoring a conversation, never during a live
  /// request. Any pending Native turn whose process-local state disappeared is
  /// durably marked UNKNOWN and is not eligible for automatic inference replay.
  Future<List<String>> recoverInterrupted({required int conversationId}) async {
    final rows = await _store.getAssistantMessages(conversationId: conversationId);
    final pending = <String, AssistantReasoningTurnRecord>{};
    final terminalIds = <String>{};
    for (final row in rows) {
      if (row['role'] != 'tool') continue;
      final event = _decode(row['metadata']);
      if (event == null || event.conversationId != conversationId) continue;
      if (event.status == AssistantReasoningTurnStatus.pending) {
        pending[event.requestId] = event;
      } else {
        terminalIds.add(event.requestId);
      }
    }

    final recovered = <String>[];
    for (final entry in pending.entries) {
      if (terminalIds.contains(entry.key)) continue;
      final result = await recordTerminal(
        conversationId: conversationId,
        requestId: entry.key,
        status: AssistantReasoningTurnStatus.unknown,
        failureCode: 'PROCESS_INTERRUPTED_WITHOUT_TERMINAL_ACK',
      );
      if (result == AssistantReasoningTurnTerminalWriteStatus.recorded ||
          result == AssistantReasoningTurnTerminalWriteStatus.alreadyRecorded) {
        recovered.add(entry.key);
      }
    }
    return List<String>.unmodifiable(recovered);
  }

  Future<AssistantReasoningTurnRecord?> load({
    required int conversationId,
    required String requestId,
  }) =>
      _read(conversationId, requestId);

  Future<AssistantReasoningTurnRecord?> _read(
    int conversationId,
    String requestId,
  ) async {
    final rows = await _store.getAssistantMessages(conversationId: conversationId);
    AssistantReasoningTurnRecord? pending;
    AssistantReasoningTurnRecord? terminal;
    for (final row in rows) {
      if (row['role'] != 'tool') continue;
      final event = _decode(row['metadata']);
      if (event == null ||
          event.conversationId != conversationId ||
          event.requestId != requestId) {
        continue;
      }
      if (event.status == AssistantReasoningTurnStatus.pending) {
        pending ??= event;
      } else {
        terminal ??= event;
      }
    }
    if (pending == null) return terminal;
    if (terminal == null) return pending;
    if (pending.mode != terminal.mode || pending.userText != terminal.userText) {
      return AssistantReasoningTurnRecord(
        conversationId: conversationId,
        requestId: requestId,
        mode: pending.mode,
        userText: pending.userText,
        createdAt: pending.createdAt,
        status: AssistantReasoningTurnStatus.unknown,
        failureCode: 'REASONING_TURN_LEDGER_IDENTITY_MISMATCH',
        interrupted: true,
      );
    }
    return terminal;
  }

  AssistantReasoningTurnRecord? _decode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['schema'] != _schema ||
          value['conversationId'] is! int ||
          value['requestId'] is! String ||
          value['mode'] is! String ||
          value['userText'] is! String ||
          value['createdAt'] is! String) {
        return null;
      }
      final rawStatus = value['kind'] == 'PENDING'
          ? 'pending'
          : value['status'] is String
              ? (value['status'] as String).toLowerCase()
              : '';
      final status = AssistantReasoningTurnStatus.values
          .where((candidate) => candidate.name == rawStatus)
          .firstOrNull;
      if (status == null) return null;
      final sourcesRaw = value['sourceIds'];
      final sourceIds = sourcesRaw is List &&
              sourcesRaw.every((item) => item is String && item.trim().isNotEmpty)
          ? List<String>.unmodifiable(sourcesRaw.cast<String>())
          : const <String>[];
      final answer = value['answerText'];
      final failure = value['failureCode'];
      if (answer != null && answer is! String) return null;
      if (failure != null && failure is! String) return null;
      return AssistantReasoningTurnRecord(
        conversationId: value['conversationId'] as int,
        requestId: value['requestId'] as String,
        mode: value['mode'] as String,
        userText: value['userText'] as String,
        createdAt: value['createdAt'] as String,
        status: status,
        answerText: answer as String?,
        sourceIds: sourceIds,
        failureCode: failure as String?,
        interrupted: value['interrupted'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  bool _sameTerminal(
    AssistantReasoningTurnRecord current, {
    required AssistantReasoningTurnStatus status,
    String? answerText,
    required List<String> sourceIds,
    String? failureCode,
  }) =>
      current.status == status &&
      current.answerText == answerText &&
      _sameList(current.sourceIds, sourceIds) &&
      current.failureCode == failureCode;

  void _validateTerminalPayload({
    required AssistantReasoningTurnStatus status,
    String? answerText,
    required List<String> sourceIds,
    String? failureCode,
  }) {
    if (status == AssistantReasoningTurnStatus.finalized) {
      if (answerText == null ||
          answerText.trim().isEmpty ||
          answerText.length > _maxAnswerCharacters ||
          failureCode != null ||
          sourceIds.any((id) => id.trim().isEmpty || id != id.trim())) {
        throw ArgumentError('REASONING_TURN_FINALIZED_PAYLOAD_INVALID');
      }
      return;
    }
    if (answerText != null ||
        sourceIds.isNotEmpty ||
        failureCode == null ||
        failureCode.trim().isEmpty ||
        failureCode != failureCode.trim()) {
      throw ArgumentError('REASONING_TURN_NON_SUCCESS_PAYLOAD_INVALID');
    }
  }

  void _validateIdentity(int conversationId, String requestId) {
    if (conversationId <= 0 ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(requestId)) {
      throw ArgumentError('REASONING_TURN_IDENTITY_INVALID');
    }
  }

  String _pendingKey(String requestId) => 'reasoning:$requestId:pending';
  String _terminalKey(String requestId) => 'reasoning:$requestId:terminal';

  bool _sameList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
