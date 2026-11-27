# P0: Native local-AI conversation transcript rehydration

## Scope

This slice addresses the confirmed Native recovery defect: when a multi-turn LiteRT-LM call fails and the Native layer creates a replacement Engine/Conversation, the replacement conversation must receive the previously completed turns. The in-flight request is not committed until a non-blank response is returned.

## API contract checked

The app pins `com.google.ai.edge.litertlm:litertlm-android:0.18.0` in `android/app/build.gradle.kts`.

The exact `0.18.0` source tag was inspected:
- [`Config.kt`](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/kotlin/java/com/google/ai/edge/litertlm/Config.kt) defines `ConversationConfig.initialMessages: List<Message>`.
- [`Message.kt`](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/kotlin/java/com/google/ai/edge/litertlm/Message.kt) defines `Message.user(String/Contents)`, `Message.model(String/Contents)` and `Role.USER` / `Role.MODEL`.
- [`Conversation.kt`](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/kotlin/java/com/google/ai/edge/litertlm/Conversation.kt) exposes synchronous `sendMessage`.

This verifies that the API shape used by the implementation exists in the pinned source tag; repository Android compilation and tests remain required.

## Base and CI

- Fresh branch base: `812288067f1bb8e28b3d5f121f8530c36f506d69` (includes PR #24 test isolation, PR #25 red-flag policy contract, and PR #23 Kotlin test pairing).
- Kotlin unit-test pairing is now part of `.github/workflows/flutter-tests.yml`; this branch must show the Android unit-test step actually ran, not skipped.

## Implementation

- `MainActivity` owns an in-memory ordered `conversationHistoryMessages` transcript.
- Only completed user/model exchanges are appended. Blank output is treated as failure and is never recorded as a completed turn.
- Every replacement conversation is created with `ConversationConfig.initialMessages` populated from a stable snapshot of the completed transcript.
- Text turns preserve the actual model input (including the context wrapper).
- Image/audio turns preserve a textual attachment marker plus prompt and model response. The temporary cache file path is deliberately not stored in replay history because Flutter may delete it after the request; replaying a stale attachment path would make later recovery fail. The live request still receives the original `ImageFile`/`AudioFile` content.
- After recovery, `conversationHasSuccessfulTurn` is derived from whether the replay transcript is non-empty, so a restored multi-turn session cannot be misclassified as a first-turn GPU fallback.
- Current failed/blank request is never appended to the completed transcript.
- After a multi-turn failure, Native restores only the prior successful transcript and returns an explicit error; it does not automatically replay the in-flight request because its execution state is unknown. Dart retains the user's text/attachment so the user can explicitly retry.
- The narrowly classified first-turn OpenCL fallback remains eligible for automatic retry under the existing `FirstTurnGpuFallbackPolicy`; it is distinct from unknown multi-turn execution state.
- CPU recovery failure preserves the original error as a suppressed exception; failed history recovery does not silently fall back to a blank conversation.

## Tests

- `LocalAiConversationHistoryPolicyTest`: user/model ordering, stable snapshot behavior, and rejection of blank user/model messages.
- The pure transcript policy stores strings/turns and maps to LiteRT-LM `Message` objects only at the `MainActivity` boundary. This is intentional: the pinned LiteRT-LM 0.18.0 `Message` class is Java class-file version 65 (Java 21), while the current Android unit-test worker runs on Java 17 (class-file version 61). Tests must not load that SDK class directly.
- Android unit tests must run through ` :app:testDebugUnitTest ` on the PR/Android CI path.
- Static branch validation alone is not proof of Android compilation.

## Known limitations / remaining acceptance

- This slice rehydrates completed turns within the current Native Activity lifetime. Cross-process transcript restoration remains driven by the existing Flutter/SQLite transcript restore path and needs its own end-to-end verification.
- Image/audio binary payloads are not retained in the replay transcript; only attachment type, prompt, and assistant output are retained. This avoids stale cache references and unbounded binary memory retention.
- Find N2 GPU/CPU behavior, multi-turn state:7 recovery, image/audio follow-up, and process recreation have not been device-verified by this code change. Keep those TRACE states UNKNOWN until captured from a real device.
- A successful CI build verifies API compatibility and tests, not that GPU/CPU model inference works on the OPPO Find N2.
