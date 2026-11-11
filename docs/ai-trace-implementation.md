# AI TRACE typed contract implementation

> 2026-11-11  
> Base: `master` @ `7c16534c7a064e1fc756a681d1099269cc77f255`  
> Workstream: F

## Implemented in this slice

- `lib/services/ai_trace.dart` defines `AiTraceContext`, `AiTraceEvent`, `AiTraceStatus`, `AiTraceStage`, and `AiTraceRecorder`.
- Recorder defaults to disabled. Disabled mode does not generate a trace ID and does not call the writer.
- Enabled mode requires an injected writer and creates a random 128-bit hex trace ID.
- Wire statuses are explicit: `NOT_STARTED`, `SUCCEEDED`, `FAILED`, `UNKNOWN`.
- Event JSON is allowlisted metadata only: trace/stage/status/time/duration, local conversation/message IDs, route/mode/tool/backend/model metadata, source IDs and error code.
- Schema intentionally has no user text, prompt/response, symptom, attachment path, OCR/ASR, birth data or identity fields.
- Writer, clock and ID-factory failures are isolated; observability cannot throw into the AI business path.

## Tests

`test/ai_trace_test.dart` covers:
- default-off: no ID generation and no writes;
- one trace ID reused across stages;
- status and stage wire serialization;
- allowlisted JSON fields;
- writer failure isolation;
- ID factory failure isolation;
- enabled mode without a writer remains disabled.

## Explicitly not implemented

- No persistent writer or retention/deletion policy.
- No user-facing audit toggle or settings persistence.
- No injection into orchestrator, retrieval, MethodChannel, Native Engine, tools, SQLite, or UI.
- No proof that trace-off runtime behavior is unchanged across the full app, because no production call sites use the recorder yet.
- No Find N2 logcat or real-device TRACE.

Therefore this is **F / PARTIAL** only. Do not mark end-to-end trace as implemented or release-ready. Next steps are a local-only opt-in writer with bounded retention, followed by single-owner incremental propagation through Dart and Native boundaries.
