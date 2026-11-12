import 'ai_trace.dart';
import 'ai_trace_store.dart';

/// Single process-wide TRACE runtime. Production instrumentation and data
/// clearing must use these same instances so recorder flush and writer clear
/// cannot race through separate queues. Recording remains disabled by default.
class AiTraceRuntime {
  AiTraceRuntime._();

  static final LocalAiTraceFileWriter writer = LocalAiTraceFileWriter();
  static final AiTraceRecorder recorder = AiTraceRecorder(
    enabled: false,
    writer: writer.call,
  );
}
