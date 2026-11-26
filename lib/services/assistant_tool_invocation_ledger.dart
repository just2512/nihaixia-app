import 'dart:convert';

import '../data/assistant_conversation_store.dart';
import '../models/assistant_tool_result.dart';

enum AssistantToolInvocationClaimStatus {
  claimed,
  alreadyClaimed,
  alreadyTerminal,
  conflictingClaim,
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
      conversationId: conversationId,
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
      final claim = existing.claim!;
      if (claim.conversationId != conversationId ||
          claim.requestId != requestId ||
          claim.toolId != toolId ||
          claim.capabilityId != capabilityId ||
          !_sameStringMap(claim.arguments, arguments)) {
        return AssistantToolInvocationClaimStatus.conflictingClaim;
      }
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
        final claim = raced.claim!;
        if (claim.conversationId != conversationId ||
            claim.requestId != requestId ||
            claim.toolId != toolId ||
            claim.capabilityId != capabilityId ||
            !_sameStringMap(claim.arguments, arguments)) {
          return AssistantToolInvocationClaimStatus.conflictingClaim;
        }
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

  /// Reads a terminal result back from the durable ledger.
  ///
  /// Only a fully revalidated SUCCEEDED record can expose result values or
  /// source IDs. Any malformed or downgraded terminal is returned as UNKNOWN
  /// with empty values and provenance, so raw executor output cannot bypass
  /// the ledger's final validation decision.
  Future<AssistantToolResult?> loadTerminalResult({
    required int conversationId,
    required String invocationId,
  }) async {
    final event = await _readInvocation(
      conversationId: conversationId,
      invocationId: invocationId,
    );
    final claim = event.claim;
    final terminal = event.terminal;
    if (claim == null || terminal == null) return null;

    final rawStatus = terminal['status'];
    AssistantToolExecutionStatus? status;
    for (final candidate in AssistantToolExecutionStatus.values) {
      if (candidate.name == rawStatus) {
        status = candidate;
        break;
      }
    }
    final rawArguments = _tryStringMap(terminal['actualArguments']);
    final actualArguments = rawArguments != null &&
            _sameStringMap(rawArguments, claim.arguments)
        ? rawArguments
        : claim.arguments;
    final titleValue = terminal['title'];
    final title = titleValue is String && titleValue.trim().isNotEmpty
        ? titleValue.trim()
        : claim.toolId;
    final rawDisclaimer = terminal['disclaimer'];
    final disclaimer = rawDisclaimer is String && rawDisclaimer.trim().isNotEmpty
        ? rawDisclaimer
        : null;
    final identityMatches =
        terminal['invocationId'] == claim.invocationId &&
        // Old terminal rows predate the explicit scope field. They remain
        // scoped by the conversation query; new rows must match the claim.
        (terminal['conversationId'] == null ||
            terminal['conversationId'] == claim.conversationId) &&
        terminal['requestId'] == claim.requestId &&
        terminal['toolId'] == claim.toolId &&
        terminal['capabilityId'] == claim.capabilityId &&
        terminal['interrupted'] is bool;
    final interrupted = terminal['interrupted'] == true;
    if (!identityMatches ||
        (status == AssistantToolExecutionStatus.succeeded && interrupted)) {
      return AssistantToolResult(
        toolId: claim.toolId,
        title: title,
        values: const <String, String>{},
        arguments: claim.arguments,
        sourceIds: const <String>[],
        status: AssistantToolExecutionStatus.unknown,
        disclaimer: '持久化终态与 claim 身份不一致或标记为中断；结果按 UNKNOWN 处理，不会重放。',
      );
    }

    if (status != AssistantToolExecutionStatus.succeeded) {
      return AssistantToolResult(
        toolId: claim.toolId,
        title: title,
        values: const <String, String>{},
        arguments: actualArguments,
        sourceIds: const <String>[],
        status: status ?? AssistantToolExecutionStatus.unknown,
        disclaimer: disclaimer ??
            (status == null
                ? '持久化执行终态无法识别；结果按 UNKNOWN 处理，不会重放。'
                : null),
      );
    }

    final values = _tryStringMap(terminal['resultValues']);
    final sourceIds = _tryStringList(terminal['sourceIds']);
    if (rawArguments == null ||
        !_sameStringMap(rawArguments, claim.arguments) ||
        values == null ||
        values.isEmpty ||
        sourceIds == null ||
        sourceIds.isEmpty) {
      return AssistantToolResult(
        toolId: claim.toolId,
        title: title,
        values: const <String, String>{},
        arguments: claim.arguments,
        sourceIds: const <String>[],
        status: AssistantToolExecutionStatus.unknown,
        disclaimer: '持久化成功记录缺少完整参数、结构化值或来源；结果按 UNKNOWN 处理，不会重放。',
      );
    }

    final candidate = AssistantToolResult(
      toolId: claim.toolId,
      title: title,
      values: values,
      arguments: rawArguments,
      sourceIds: sourceIds,
      status: AssistantToolExecutionStatus.succeeded,
      disclaimer: disclaimer,
    );
    if (candidate.validateFor(claim.toolId).isEmpty &&
        candidate.validateArgumentsMatch(claim.arguments).isEmpty) {
      return candidate;
    }
    return AssistantToolResult(
      toolId: claim.toolId,
      title: title,
      values: const <String, String>{},
      arguments: claim.arguments,
      sourceIds: const <String>[],
      status: AssistantToolExecutionStatus.unknown,
      disclaimer: '持久化成功记录未通过终态复核；结果按 UNKNOWN 处理，不会重放。',
    );
  }

  Map<String, String>? _tryStringMap(Object? raw) {
    if (raw is! Map) return null;
    final result = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) return null;
      result[entry.key as String] = entry.value as String;
    }
    return Map<String, String>.unmodifiable(result);
  }

  List<String>? _tryStringList(Object? raw) {
    if (raw is! List) return null;
    final result = <String>[];
    for (final item in raw) {
      if (item is! String || item.trim().isEmpty || item != item.trim()) {
        return null;
      }
      result.add(item);
    }
    return List<String>.unmodifiable(result);
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
        'conversationId': claim.conversationId,
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
        final latestStatus = latest.terminal!['status'];
        final interrupted = latest.terminal!['interrupted'] == true;
        if (latestStatus != AssistantToolExecutionStatus.unknown.name ||
            !interrupted) {
          continue;
        }
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
      'conversationId': claim.conversationId,
      'invocationId': invocationId,
      'requestId': claim.requestId,
      'toolId': claim.toolId,
      'capabilityId': claim.capabilityId,
      'title': result.title,
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

  bool _sameStringMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    return a.entries.every((entry) => b[entry.key] == entry.value);
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
    required int conversationId,
    required String invocationId,
    required String requestId,
    required String toolId,
    required String capabilityId,
    required Map<String, String> arguments,
  }) {
    if (conversationId <= 0) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(requestId)) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Expected a 32-character hexadecimal request ID',
      );
    }
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
            entry.key.length > 128 ||
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

  String get invocationId {
    final currentClaim = claim;
    if (currentClaim != null) return currentClaim.invocationId;
    final terminalId = terminal?['invocationId'];
    if (terminalId is String) return terminalId;
    throw StateError('Invocation event is missing its identity');
  }

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
        if (decoded['conversationId'] is! int ||
            decoded['requestId'] is! String ||
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
            conversationId: decoded['conversationId'] as int,
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
          decoded['status'] is String &&
          AssistantToolExecutionStatus.values
              .any((status) => status.name == decoded['status']) &&
          (decoded['conversationId'] == null ||
              decoded['conversationId'] is int) &&
          decoded['requestId'] is String &&
          decoded['toolId'] is String &&
          decoded['capabilityId'] is String &&
          decoded['actualArguments'] is Map &&
          decoded['resultValues'] is Map &&
          decoded['sourceIds'] is List) {
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
