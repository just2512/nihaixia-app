import 'dart:async';
import 'dart:math';

/// Execution state is deliberately separate from UI/network exception labels.
enum AiTraceStatus {
  notStarted,
  succeeded,
  failed,
  unknown,
  notApplicable;

  String get wireValue => switch (this) {
        AiTraceStatus.notStarted => 'NOT_STARTED',
        AiTraceStatus.succeeded => 'SUCCEEDED',
        AiTraceStatus.failed => 'FAILED',
        AiTraceStatus.unknown => 'UNKNOWN',
        AiTraceStatus.notApplicable => 'NOT_APPLICABLE',
      };
}

enum AiTraceStage {
  input,
  preflight,
  redFlag,
  dispatch,
  route,
  entityResolution,
  retrieval,
  contextAssembly,
  modelInput,
  modelOutput,
  nativeInference,
  toolExecution,
  argumentValidation,
  businessExecution,
  resultValidation,
  persistence,
  persistedState,
  presentation,
  finalRender;

  String get wireValue => name.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '\u005f${match.group(0)!.toLowerCase()}',
      ).toUpperCase();
}

class AiTraceContext {
  const AiTraceContext._({
    required this.enabled,
    this.traceId,
    this.startedAt,
  });

  const AiTraceContext.disabled()
      : this._(enabled: false);

  const AiTraceContext.enabled({
    required String traceId,
    required DateTime startedAt,
  }) : this._(
          enabled: true,
          traceId: traceId,
          startedAt: startedAt,
        );

  final bool enabled;
  final String? traceId;
  final DateTime? startedAt;
}

/// Allowlisted metadata only. This type intentionally has no user-text,
/// prompt, response, symptom, attachment, OCR/ASR, birth-data or identity field.
class AiTraceEvent {
  const AiTraceEvent({
    required this.traceId,
    required this.stage,
    required this.status,
    required this.occurredAt,
    this.durationMs,
    this.conversationId,
    this.messageId,
    this.route,
    this.mode,
    this.toolId,
    this.backend,
    this.modelVersion,
    this.sourceIds = const <String>[],
    this.errorCode,
  });

  final String traceId;
  final AiTraceStage stage;
  final AiTraceStatus status;
  final DateTime occurredAt;
  final int? durationMs;
  final int? conversationId;
  final int? messageId;
  final String? route;
  final String? mode;
  final String? toolId;
  final String? backend;
  final String? modelVersion;
  final List<String> sourceIds;
  final String? errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': 1,
        'trace_id': traceId,
        'stage': stage.wireValue,
        'status': status.wireValue,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        if (durationMs != null) 'duration_ms': durationMs,
        if (conversationId != null) 'conversation_id': conversationId,
        if (messageId != null) 'message_id': messageId,
        if (route != null) 'route': route,
        if (mode != null) 'mode': mode,
        if (toolId != null) 'tool_id': toolId,
        if (backend != null) 'backend': backend,
        if (modelVersion != null) 'model_version': modelVersion,
        if (sourceIds.isNotEmpty) 'source_ids': List<String>.unmodifiable(sourceIds),
        if (errorCode != null) 'error_code': errorCode,
      };
}

typedef AiTraceEventWriter = Future<void> Function(AiTraceEvent event);
typedef AiTraceIdFactory = String Function();
typedef AiTraceClock = DateTime Function();

/// Default-off, best-effort metadata recorder. A missing writer or disabled
/// flag means no ID generation and no writes. Writer failures never propagate
/// into the AI business flow.
class AiTraceRecorder {
  AiTraceRecorder({
    bool enabled = false,
    AiTraceEventWriter? writer,
    AiTraceIdFactory? idFactory,
    AiTraceClock? clock,
  })  : _enabled = enabled && writer != null,
        _writer = writer,
        _idFactory = idFactory ?? _secureTraceId,
        _clock = clock ?? DateTime.now;

  final bool _enabled;
  final AiTraceEventWriter? _writer;
  final AiTraceIdFactory _idFactory;
  final AiTraceClock _clock;

  AiTraceContext start({
    required AiTraceStage stage,
    String? route,
    String? mode,
  }) {
    if (!_enabled) return const AiTraceContext.disabled();
    try {
      final startedAt = _clock();
      final traceId = _idFactory();
      if (traceId.trim().isEmpty) return const AiTraceContext.disabled();
      final context = AiTraceContext.enabled(
        traceId: traceId,
        startedAt: startedAt,
      );
      unawaited(_writeSafely(AiTraceEvent(
        traceId: traceId,
        stage: stage,
        status: AiTraceStatus.notStarted,
        occurredAt: startedAt,
        route: route,
        mode: mode,
      )));
      return context;
    } catch (_) {
      // Failure to create an audit identifier must not block the user request.
      return const AiTraceContext.disabled();
    }
  }

  Future<void> record(
    AiTraceContext context, {
    required AiTraceStage stage,
    required AiTraceStatus status,
    int? durationMs,
    int? conversationId,
    int? messageId,
    String? route,
    String? mode,
    String? toolId,
    String? backend,
    String? modelVersion,
    List<String> sourceIds = const <String>[],
    String? errorCode,
  }) async {
    final traceId = context.traceId;
    if (!_enabled || !context.enabled || traceId == null || traceId.isEmpty) {
      return;
    }
    try {
      await _writeSafely(AiTraceEvent(
        traceId: traceId,
        stage: stage,
        status: status,
        occurredAt: _clock(),
        durationMs: durationMs == null ? null : (durationMs < 0 ? 0 : durationMs),
        conversationId: conversationId,
        messageId: messageId,
        route: route,
        mode: mode,
        toolId: toolId,
        backend: backend,
        modelVersion: modelVersion,
        sourceIds: List<String>.unmodifiable(sourceIds),
        errorCode: errorCode,
      ));
    } catch (_) {
      // Clock/metadata failures must not escape into the AI business flow.
    }
  }

  Future<void> _writeSafely(AiTraceEvent event) async {
    try {
      await _writer?.call(event);
    } catch (_) {
      // Observability is best-effort and must never block AI execution.
    }
  }

  static String _secureTraceId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
