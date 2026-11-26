import 'dart:convert';

import '../data/assistant_conversation_store.dart';
import '../models/assistant_tool_result.dart';

enum AssistantToolInvocationClaimStatus {
  claimed,
  alreadyClaimed,
  alreadyTerminal,
}

enum AssistantToolInvocationTerminalWriteStatus {
  recorded,
  alreadyRecorded,
  missingClaim,
  conflictingTerminal,
}

class AssistantToolInvocationClaim {
  const AssistantToolInvocationClaim({
    required this.conversationId,
    required this.invocationId,
    required this.requestId,
    required this.toolId,
    required this.capabilityId,
    required this.arguments,
    required this.createdAt,
  });

  final int conversationId;
  final String invocationId;
  final String requestId;
  final String toolId;
  final String capabilityId;
  final Map<String, String> arguments;
  final String createdAt;
}

class AssistantToolInvocationLedger {
  const AssistantToolInvocationLedger(this._store);

  final AssistantConversationStore _store;

  static const String _schema = 'assistant-tool-invocation-v1';
  static const String _claimKind = 'CLAIMED';
  static const String _terminalKind = 'TERMINAL';
  static const int _maxIdentifierLength = 128;

  /// Durably claims one invocation before any business executor is called.
  ///
  /// The SQLite partial unique index on (conversation_id, invocation_key)
  /// provides the cross-process single-claim guarantee. The in-memory store
  /// implements the same uniqueness rule for widget/unit tests.
  Future<AssistantToolInvocationClaimStatus> tryClaim({
    required int conversationId,
    required String invocationId,
    required String requestId,
    required String toolId,
    required String capabilityId,
    required Map<String, String> arguments,
  }) async {
    _validateInput(
      invocationId: invocationId,
      requestId: requestId,
      toolId: toolId,
      capabilityId: capabilityId,
      arguments: arguments,
    );

    final existing = await _readInvocation(
      conversationId: conversationId,
      invocationId: invocationId,
    );
    if (existing.claim != null) {
      return existing.terminal == null
          ? AssistantToolInvocationClaimStatus.alreadyClaimed
          : AssistantToolInvocationClaimStatus.alreadyTerminal;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, Object?>{
      'schema': _schema,
      'kind': _claimKind,
      'conversationId': conversationId,
      'invocationId': invocationId,
      'requestId': requestId,
      'toolId': toolId,
      'capabilityId': capabilityId,
      'arguments': Map<String, String>.unmodifiable(arguments),
      'createdAt': now,
    };
    try {
      await _store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'tool',
        content: 'TOOL_INVOCATION_CLAIMED',
        metadata: jsonEncode(payload),
        invocationKey: _claimKey(invocationId),
      );
      return AssistantToolInvocationClaimStatus.claimed;
    } catch (_) {
      // A concurrent claimant can win the unique index after our read.
      // Re-read and classify only if the winning claim is now visible.
      final raced = await _readInvocation(
        conversationId: conversationId,
        invocationId: invocationId,
      );
      if (raced.claim != null) {
        return raced.terminal == null
            ? AssistantToolInvocationClaimStatus.alreadyClaimed
            : AssistantToolInvocationClaimStatus.alreadyTerminal;
      }
      rethrow;
    }
  }

  /// Persists the real executor result exactly once after validating its scope.
  ///
  /// Invalid success provenance or argument mismatch is recorded as UNKNOWN,
  /// not SUCCEEDED. The original returned values remain in the hidden ledger
  /// row for diagnosis, while consumers must treat the terminal state as
  /// non-replayable and non-successful.
  Future<AssistantToolInvocationTerminalWriteStatus> recordResult({
    required int conversationId,
    required String invocationId,
    required AssistantToolResult result,
  }) async {
    final current = await _readInvocation(
      conversationId: conversationId,
      invocationId: invocationId,
    );
    final claim = current.claim;
    if (claim == null) {
      return AssistantToolInvocationTerminalWriteStatus.missingClaim;
    }

    final payload = _terminalPayload(
      invocationId: invocationId,
      claim: claim,
      result: result,
      interrupted: false,
    );
    if (current.terminal != null) {
      return _sameTerminal(current.terminal!, payload)
          ? AssistantToolInvocationTerminalWriteStatus.alreadyRecorded
          : AssistantToolInvocationTerminalWriteStatus.conflictingTerminal;
    }

    try {
      await _store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'tool',
        content: 'TOOL_INVOCATION_TERMINAL',
        metadata: jsonEncode(payload),
        invocationKey: _terminalKey(invocationId),
      );
      return AssistantToolInvocationTerminalWriteStatus.recorded;
    } catch (_) {
      final raced = await _readInvocation(
        conversationId: conversationId,
        invocationId: invocationId,
      );
      if (raced.terminal != null) {
        return _sameTerminal(raced.terminal!, payload)
            ? AssistantToolInvocationTerminalWriteStatus.alreadyRecorded
            : AssistantToolInvocationTerminalWriteStatus.conflictingTerminal;
      }
      rethrow;
    }
  }

  /// Converts claims left without a terminal result into UNKNOWN.
  ///
  /// Call only when restoring/opening a conversation, not while a live
  /// executor may still be running. An interrupted invocation is never
  /// automatically replayed, even when it might have crashed before dispatch.
  Future<List<String>> recoverUnresolvedClaims({
    required int conversationId,
  }) async {
    final rows = await _store.getAssistantMessages(
      conversationId: conversationId,
    );
    final events = <String, _InvocationEvent>{};
    for (final row in rows) {
      if (row['role'] != 'tool') continue;
      final event = _InvocationEvent.tryDecode(row['metadata']);
      if (event == null) continue;
      events[event.invocationId] = (events[event.invocationId] ?? const _InvocationEvent())
          .merge(event);
    }

    final recovered = <String>[];
    for (final entry in events.entries) {
      final event = entry.value;
      final claim = event.claim;
      if (claim == null || event.terminal != null) continue;
      final payload = <String, Object?>{
        'schema': _schema,
        'kind': _terminalKind,
        'invocationId': claim.invocationId,
        'requestId': claim.requestId,
        'toolId': claim.toolId,
        'capabilityId': claim.capabilityId,
        'status': AssistantToolExecutionStatus.unknown.name,
        'actualArguments': claim.arguments,
        'resultValues': const <String, String>{},
        'sourceIds': const <String>[],
        'failureCode': 'PROCESS_INTERRUPTED_WITHOUT_TERMINAL_RESULT',
        'disclaimer':
            '进程恢复时发现调用已领取但没有持久化终态。无法判断业务动作是否已发生，不会自动重放。',
        'interrupted': true,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        await _store.saveAssistantMessage(
          conversationId: conversationId,
          role: 'tool',
          content: 'TOOL_INVOCATION_UNKNOWN',
          metadata: jsonEncode(payload),
          invocationKey: _terminalKey(claim.invocationId),
        );
      } catch (_) {
        // If another recovery worker wrote the terminal first, verify it.
        final latest = await _readInvocation(
          conversationId: conversationId,
          invocationId: claim.invocationId,
        );
        if (latest.terminal == null) rethrow;
      }
      recovered.add(claim.invocationId);
    }
    return List<String>.unmodifiable(recovered);
  }

  Future<List<AssistantToolInvocationClaim>> listUnresolvedClaims({
    required int conversationId,
  }) async {
    final rows = await _store.getAssistantMessages(
      conversationId: conversationId,
    );
    final events = <String, _InvocationEvent>{};
    for (final row in rows) {
      if (row['role'] != 'tool') continue;
      final event = _InvocationEvent.tryDecode(row['metadata']);
      if (event == null) continue;
      events[event.invocationId] = (events[event.invocationId] ?? const _InvocationEvent())
          .merge(event);
    }
    return List<AssistantToolInvocationClaim>.unmodifiable([
      for (final event in events.values)
        if (event.claim != null && event.terminal == null) event.claim!,
    ]);
  }

  Future<_InvocationEvent> _readInvocation({
    required int conversationId,
    required String invocationId,
  }) async {
    final rows = await _store.getAssistantMessages(
      conversationId: conversationId,
    );
    var event = const _InvocationEvent();
    for (final row in rows) {
      if (row['role'] != 'tool') continue;
      final decoded = _InvocationEvent.tryDecode(row['metadata']);
      if (decoded == null || decoded.invocationId != invocationId) continue;
      event = event.merge(decoded);
    }
    return event;
  }

  Map<String, Object?> _terminalPayload({
    required String invocationId,
    required AssistantToolInvocationClaim claim,
    required AssistantToolResult result,
    required bool interrupted,
  }) {
    final identityErrors = <String>[];
    if (result.toolId != claim.toolId) identityErrors.add('TOOL_ID_MISMATCH');
    if (result.title.trim().isEmpty) identityErrors.add('RESULT_TITLE_MISSING');
    if (result.validateArgumentsMatch(claim.arguments).isNotEmpty) {
      identityErrors.add('ACTUAL_ARGUMENTS_MISMATCH');
    }
    final resultErrors = result.validateFor(claim.toolId);
    final isValidSuccess = result.status == AssistantToolExecutionStatus.succeeded &&
        identityErrors.isEmpty &&
        resultErrors.isEmpty;
    final effectiveStatus = identityErrors.isNotEmpty ||
            (result.status == AssistantToolExecutionStatus.succeeded && !isValidSuccess)
        ? AssistantToolExecutionStatus.unknown
        : result.status;
    return <String, Object?>{
      'schema': _schema,
      'kind': _terminalKind,
      'invocationId': invocationId,
      'requestId': claim.requestId,
      'toolId': claim.toolId,
      'capabilityId': claim.capabilityId,
      'status': effectiveStatus.name,
      'actualArguments': Map<String, String>.unmodifiable(result.arguments),
      'resultValues': Map<String, String>.unmodifiable(result.values),
      'sourceIds': List<String>.unmodifiable(result.sourceIds),
      if (identityErrors.isNotEmpty || resultErrors.isNotEmpty)
        'failureCode': [
          ...identityErrors,
          ...resultErrors.map((_) => 'RESULT_VALIDATION_FAILED'),
        ].join('|'),
      if (result.disclaimer != null) 'disclaimer': result.disclaimer,
      'interrupted': interrupted,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  bool _sameTerminal(
    Map<String, Object?> existing,
    Map<String, Object?> candidate,
  ) {
    final left = Map<String, Object?>.from(existing)..remove('createdAt');
    final right = Map<String, Object?>.from(candidate)..remove('createdAt');
    return jsonEncode(_canonical(left)) == jsonEncode(_canonical(right));
  }

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.whereType<String>().toList()..sort();
      return {
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  void _validateInput({
    required String invocationId,
    required String requestId,
    required String toolId,
    required String capabilityId,
    required Map<String, String> arguments,
  }) {
    for (final entry in {
      'invocationId': invocationId,
      'requestId': requestId,
      'toolId': toolId,
      'capabilityId': capabilityId,
    }.entries) {
      if (entry.value.trim().isEmpty ||
          entry.value != entry.value.trim() ||
          entry.value.length > _maxIdentifierLength) {
        throw ArgumentError.value(entry.value, entry.key);
      }
    }
    if (arguments.length > 32 ||
        arguments.entries.any((entry) =>
            entry.key.trim().isEmpty ||
            entry.key != entry.key.trim() ||
            entry.value.length > 2048)) {
      throw ArgumentError.value(arguments, 'arguments');
    }
  }

  String _claimKey(String invocationId) => '$invocationId:claim';
  String _terminalKey(String invocationId) => '$invocationId:terminal';
}

class _InvocationEvent {
  const _InvocationEvent({
    this.claim,
    this.terminal,
  });

  final AssistantToolInvocationClaim? claim;
  final Map<String, Object?>? terminal;

  _InvocationEvent merge(_InvocationEvent other) => _InvocationEvent(
        claim: other.claim ?? claim,
        terminal: other.terminal ?? terminal,
      );

  static _InvocationEvent? tryDecode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != AssistantToolInvocationLedger._schema ||
          decoded['invocationId'] is! String) {
        return null;
      }
      final kind = decoded['kind'];
      if (kind == AssistantToolInvocationLedger._claimKind) {
        if (decoded['requestId'] is! String ||
            decoded['toolId'] is! String ||
            decoded['capabilityId'] is! String ||
            decoded['arguments'] is! Map ||
            decoded['createdAt'] is! String) {
          return null;
        }
        final args = <String, String>{};
        for (final entry in (decoded['arguments'] as Map).entries) {
          if (entry.key is! String || entry.value is! String) return null;
          args[entry.key as String] = entry.value as String;
        }
        return _InvocationEvent(
          claim: AssistantToolInvocationClaim(
            conversationId: decoded['conversationId'] is int
                ? decoded['conversationId'] as int
                : 0,
            invocationId: decoded['invocationId'] as String,
            requestId: decoded['requestId'] as String,
            toolId: decoded['toolId'] as String,
            capabilityId: decoded['capabilityId'] as String,
            arguments: Map<String, String>.unmodifiable(args),
            createdAt: decoded['createdAt'] as String,
          ),
        );
      }
      if (kind == AssistantToolInvocationLedger._terminalKind &&
          decoded['status'] is String) {
        return _InvocationEvent(
          terminal: Map<String, Object?>.from(decoded),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
