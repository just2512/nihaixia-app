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

## Implementation

- `MainActivity` owns an in-memory ordered `conversationHistoryMessages` transcript.
- Only completed user/model exchanges are appended. Blank output is treated as failure and is never recorded as a completed turn.
- Every replacement conversation is created with `ConversationConfig.initialMessages` populated from a stable snapshot of the completed transcript.
- Text turns preserve the actual model input (including the context wrapper).
- Image/audio turns preserve a textual attachment marker plus prompt and model response. The temporary cache file path is deliberately not stored in replay history because Flutter may delete it after the request; replaying a stale attachment path would make later recovery fail. The live request still receives the original `ImageFile`/`AudioFile` content.
- After recovery, `conversationHasSuccessfulTurn` is derived from whether the replay transcript is non-empty, so a restored multi-turn session cannot be misclassified as a first-turn GPU fallback.
- Current failed/blank request is appended only after its retry succeeds.
- CPU recovery failure and retry failure preserve the original error as a suppressed exception; failed history recovery does not silently fall back to a blank conversation.

## Tests

- `LocalAiConversationHistoryPolicyTest`: user/model ordering, stable snapshot behavior, and rejection of blank responses.
- Android unit tests must run through ` :app:testDebugUnitTest ` on the PR/Android CI path.
- Static branch validation alone is not proof of Android compilation.

## Known limitations / remaining acceptance

- This slice rehydrates completed turns within the current Native Activity lifetime. Cross-process transcript restoration remains driven by the existing Flutter/SQLite transcript restore path and needs its own end-to-end verification.
- Image/audio binary payloads are not retained in the replay transcript; only attachment type, prompt, and assistant output are retained. This avoids stale cache references and unbounded binary memory retention.
- Find N2 GPU/CPU behavior, multi-turn state:7 recovery, image/audio follow-up, and process recreation have not been device-verified by this code change. Keep those TRACE states UNKNOWN until captured from a real device.
- A successful CI build verifies API compatibility and tests, not that GPU/CPU model inference works on the OPPO Find N2.
