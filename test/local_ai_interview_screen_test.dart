import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/models/bookmark.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';
import 'package:nihaisha_app/services/ai_trace.dart';
import 'package:nihaisha_app/services/assistant_conversation_orchestrator.dart';
import 'package:nihaisha_app/services/tcm_interview_adapter.dart';
import 'package:nihaisha_app/services/xiaoliuren_tool_executor.dart';
import 'package:nihaisha_app/services/yijing_tool_executor.dart';
import 'package:nihaisha_app/services/dosage_tool_executor.dart';
import 'package:nihaisha_app/services/ziwuliuzhu_tool_executor.dart';
import 'package:nihaisha_app/services/local_ai_attachment_store.dart';
import 'package:nihaisha_app/services/red_flag_gate.dart';
import 'package:nihaisha_app/services/red_flag_preflight.dart';
import 'package:record/record.dart';

const _readyStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: true,
  modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'cpu',
);

class _MemoryConversationStore implements AssistantConversationStore {
  int _nextConversationId = 1;
  int _nextMessageId = 1;
  int createConversationCalls = 0;
  int taskStateSaveCalls = 0;
  bool failNextMessageBatch = false;
  bool failNextSingleMessageSave = false;
  bool failNextTaskStateSave = false;
  final Map<int, Map<String, Object?>> _conversations = {};
  final Map<int, List<Map<String, Object?>>> _messages = {};
  final Map<int, TcmInterviewTaskState> _taskStates = {};

  @override
  Future<int> createAssistantConversation({
    String title = '新对话',
    String mode = 'general',
  }) async {
    createConversationCalls += 1;
    final id = _nextConversationId++;
    final now = DateTime.now().toIso8601String();
    _conversations[id] = {
      'id': id,
      'title': title,
      'mode': mode,
      'created_at': now,
      'updated_at': now,
      'last_message_preview': '',
    };
    _messages[id] = [];
    return id;
  }

  @override
  Future<int> saveAssistantMessage({
    required int conversationId,
    required String role,
    required String content,
    String? metadata,
  }) async {
    if (failNextSingleMessageSave) {
      failNextSingleMessageSave = false;
      throw StateError('INJECTED_SINGLE_MESSAGE_SAVE_FAILURE');
    }
    final id = _nextMessageId++;
    _messages.putIfAbsent(conversationId, () => []).add({
      'id': id,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'metadata': metadata,
    });
    final conversation = _conversations[conversationId];
    if (conversation != null) {
      conversation['updated_at'] = DateTime.now().toIso8601String();
      conversation['last_message_preview'] = content;
    }
    return id;
  }

  @override
  Future<int> saveAssistantTurn({
    required int conversationId,
    String? userContent,
    String? userMetadata,
    required String assistantContent,
    String? assistantMetadata,
  }) async {
    if (userContent != null && userContent.trim().isNotEmpty) {
      await saveAssistantMessage(
        conversationId: conversationId,
        role: 'user',
        content: userContent,
        metadata: userMetadata,
      );
    }
    return saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: assistantContent,
      metadata: assistantMetadata,
    );
  }

  @override
  Future<List<int>> saveAssistantMessagesAtomically({
    required int conversationId,
    required List<AssistantMessageDraft> messages,
  }) async {
    if (failNextMessageBatch) {
      failNextMessageBatch = false;
      throw StateError('INJECTED_MESSAGE_BATCH_FAILURE');
    }
    final ids = <int>[];
    for (final message in messages) {
      ids.add(await saveAssistantMessage(
        conversationId: conversationId,
        role: message.role,
        content: message.content,
        metadata: message.metadata,
      ));
    }
    return ids;
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  }) async {
    final rows = _conversations.values
        .where((row) => (_messages[row['id']] ?? const []).isNotEmpty)
        .toList()
      ..sort((a, b) =>
          (b['updated_at'] as String).compareTo(a['updated_at'] as String));
    return limit == null ? rows : rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  }) async =>
      List<Map<String, Object?>>.from(_messages[conversationId] ?? const []);

  @override
  Future<void> saveTcmInterviewTaskState({
    required int conversationId,
    required TcmInterviewTaskState state,
  }) async {
    taskStateSaveCalls += 1;
    if (failNextTaskStateSave) {
      failNextTaskStateSave = false;
      throw StateError('INJECTED_TASK_STATE_FAILURE');
    }
    _taskStates[conversationId] = state;
  }

  @override
  Future<TcmInterviewTaskState?> getTcmInterviewTaskState({
    required int conversationId,
  }) async =>
      _taskStates[conversationId];

  @override
  Future<void> deleteAssistantConversations(List<int> conversationIds) async {
    for (final id in conversationIds) {
      _conversations.remove(id);
      _messages.remove(id);
      _taskStates.remove(id);
    }
  }
}

_MemoryConversationStore _store = _MemoryConversationStore();

Future<TcmInterviewTaskState?> _waitForTcmInterviewTaskState(
  WidgetTester tester, {
  int? conversationId,
  String? expectedPendingPromptId,
  bool expectedPromptIdStartsWith = false,
}) async {
  // WidgetTester.pumpAndSettle only waits for scheduled frames; the screen's
  // persistence future may still be completing after the last frame. Poll for
  // the expected state, not merely a non-null snapshot that may be stale.
  TcmInterviewTaskState? latest;
  for (var attempt = 0; attempt < 30; attempt++) {
    final candidateIds = conversationId == null
        ? _store._conversations.keys.toList(growable: false).reversed
        : [conversationId];
    for (final id in candidateIds) {
      latest = await _store.getTcmInterviewTaskState(conversationId: id);
      final pendingId = latest?.pendingPromptId;
      final matchesExpected = expectedPendingPromptId == null ||
          (expectedPromptIdStartsWith
              ? pendingId?.startsWith(expectedPendingPromptId) == true
              : pendingId == expectedPendingPromptId);
      if (latest != null && matchesExpected) return latest;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
  return latest;
}

class _FailOnceStopRecorder implements LocalAiAudioRecorder {
  _FailOnceStopRecorder({this.failFirstStop = true});

  final bool failFirstStop;
  int stopCalls = 0;
  String? _path;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _path = path;
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    if (failFirstStop && stopCalls == 1) {
      throw PlatformException(
        code: 'STOP_FAILED',
        message: '模拟录音停止失败',
      );
    }
    return _path;
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingRecordingFileInspector
    implements LocalAiRecordingFileInspector {
  @override
  Future<int?> sizeBytes(String path) async {
    throw StateError('模拟停止后文件读取失败');
  }
}

class _ValidRecordingFileInspector
    implements LocalAiRecordingFileInspector {
  @override
  Future<int?> sizeBytes(String path) async => 4;
}

class _FakeRecordingAttachmentStore extends LocalAiAttachmentStore {
  _FakeRecordingAttachmentStore(this.path);

  final String path;

  @override
  Future<String> createRecordingPath({String extension = '.wav'}) async =>
      path;
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

class _EmptyLocalAiImagePicker implements LocalAiImagePicker {
  @override
  Future<String?> retrieveLostImagePath() async => null;

  @override
  Future<String?> pickCameraImagePath() async => null;

  @override
  Future<String?> pickGalleryImagePath() async => null;
}

class _DeferredLocalAiImagePicker implements LocalAiImagePicker {
  final retrieveResult = Completer<String?>();
  final pickResult = Completer<String?>();
  var retrieveCalls = 0;
  var pickCalls = 0;

  @override
  Future<String?> retrieveLostImagePath() {
    retrieveCalls += 1;
    return retrieveResult.future;
  }

  @override
  Future<String?> pickCameraImagePath() {
    pickCalls += 1;
    return pickResult.future;
  }

  @override
  Future<String?> pickGalleryImagePath() async => null;
}

class _DeferredModelControlService extends _TextSendService {
  final resetResult = Completer<LocalAiModelStatus>();
  final releaseResult = Completer<LocalAiModelStatus>();
  var resetCalls = 0;
  var releaseCalls = 0;

  @override
  Future<LocalAiModelStatus> resetConversation() {
    resetCalls += 1;
    return resetResult.future;
  }

  @override
  Future<LocalAiModelStatus> releaseModel() {
    releaseCalls += 1;
    return releaseResult.future;
  }
}

class _SourceTruncatedEmptySymptomsService extends _TextSendService {
  @override
  Future<LocalAiSymptomDraft> extractSymptoms() async {
    return const LocalAiSymptomDraft(sourceTruncated: true);
  }
}

class _SourceTruncatedSymptomsService extends _TextSendService {
  @override
  Future<LocalAiSymptomDraft> extractSymptoms() async {
    return const LocalAiSymptomDraft(
      mainComplaint: '间断头痛',
      sourceTruncated: true,
    );
  }
}

class _PageToolTraceService extends _TextSendService {
  final restoredTranscripts = <String>[];

  @override
  Future<LocalAiIntentResolution> resolveAssistantIntentWithTrace({
    required String query,
    required List<LocalAiIntentCandidate> candidates,
    required String traceId,
  }) async {
    intentQueries.add(query);
    intentCandidateIds.add(candidates.map((candidate) => candidate.id).toList());
    intentTraceIds.add(traceId);
    return intentResolution;
  }

  @override
  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
  }) async {
    restoredTranscripts.add(transcript);
  }
}

class _SequencedSymptomsTraceService extends _TextSendService {
  final List<LocalAiSymptomDraft> drafts;
  final extractedTraceIds = <String>[];

  _SequencedSymptomsTraceService(this.drafts);

  @override
  Future<LocalAiSymptomDraft> extractSymptomsWithTrace({
    required String traceId,
  }) async {
    extractedTraceIds.add(traceId);
    return drafts.removeAt(0);
  }
}

class _TextSendService extends LocalAiService {
  _TextSendService({
    this.intentResolution = const LocalAiIntentResolution(
      action: LocalAiIntentAction.clarify,
    ),
    this.baziSlotDraft,
  });

  final LocalAiIntentResolution intentResolution;
  final LocalAiBaziSlotDraft? baziSlotDraft;
  int statusCalls = 0;
  final baziSlotQueries = <String>[];
  final baziSlotMissingKeys = <Set<String>>[];
  final baziSlotTraceIds = <String>[];
  final intentQueries = <String>[];
  final intentCandidateIds = <List<String>>[];
  final intentTraceIds = <String>[];
  final sentTexts = <String>[];
  final sentContexts = <String>[];
  final sentTraceIds = <String>[];
  final restoredTranscripts = <String>[];

  @override
  Future<LocalAiBaziSlotDraft> extractBaziSlotsWithTrace({
    required String query,
    required Set<String> missingKeys,
    required String traceId,
  }) async {
    baziSlotQueries.add(query);
    baziSlotMissingKeys.add(Set<String>.unmodifiable(missingKeys));
    baziSlotTraceIds.add(traceId);
    return baziSlotDraft ?? const LocalAiBaziSlotDraft(values: {});
  }

  @override
  Future<LocalAiIntentResolution> resolveAssistantIntentWithTrace({
    required String query,
    required List<LocalAiIntentCandidate> candidates,
    required String traceId,
  }) async {
    intentQueries.add(query);
    intentCandidateIds.add(candidates.map((candidate) => candidate.id).toList());
    intentTraceIds.add(traceId);
    return intentResolution;
  }

  @override
  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
  }) async {
    restoredTranscripts.add(transcript);
  }

  @override
  Future<LocalAiModelStatus> getStatus() async {
    statusCalls += 1;
    return _readyStatus;
  }

  @override
  Future<String> sendMessage(String text) async {
    sentTexts.add(text);
    return '已收到你的描述：$text';
  }

  @override
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
  }) async {
    sentContexts.add(context);
    return sendMessage(text);
  }

  @override
  Future<String> sendMessageWithTrace(
    String text, {
    required String traceId,
  }) async {
    sentTraceIds.add(traceId);
    return sendMessage(text);
  }

  @override
  Future<String> sendMessageWithContextAndTrace(
    String text, {
    required String context,
    required String traceId,
  }) async {
    sentTraceIds.add(traceId);
    sentContexts.add(context);
    return sendMessage(text);
  }
}

class _FailingIntentSelectionService extends _TextSendService {
  @override
  Future<LocalAiIntentResolution> resolveAssistantIntentWithTrace({
    required String query,
    required List<LocalAiIntentCandidate> candidates,
    required String traceId,
  }) async {
    intentQueries.add(query);
    intentCandidateIds.add(candidates.map((candidate) => candidate.id).toList());
    intentTraceIds.add(traceId);
    throw PlatformException(
      code: 'INTENT_CLASSIFICATION_FAILED',
      message: 'intent classification unavailable in test',
    );
  }
}

class _FailingTextSendService extends _TextSendService {
  @override
  Future<String> sendMessageWithTrace(
    String text, {
    required String traceId,
  }) async {
    throw PlatformException(
      code: 'NATIVE_SEND_FAILED',
      message: 'native send failed in test',
    );
  }
}

const _releasedStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: false,
  modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'not_loaded',
);

class _HashVerificationFailureService extends LocalAiService {
  var _hashVerified = true;
  var loadCalls = 0;
  var statusCalls = 0;

  @override
  Future<LocalAiModelStatus> getStatus() async {
    statusCalls += 1;
    return LocalAiModelStatus(
      installed: true,
      fileExists: true,
      hashVerified: _hashVerified,
      ready: false,
      modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
      sizeBytes: 3659530240,
      expectedSizeBytes: 3659530240,
      backend: 'not_loaded',
    );
  }

  @override
  Future<LocalAiModelStatus> loadModel() async {
    loadCalls += 1;
    _hashVerified = false;
    throw PlatformException(
      code: 'MODEL_HASH_MISMATCH',
      message: '模型 SHA-256 校验失败，请重新导入',
    );
  }
}

class _DeferredModelSetupService extends LocalAiService {
  final loadResult = Completer<LocalAiModelStatus>();
  final importResult = Completer<LocalAiModelStatus>();
  var loadCalls = 0;
  var importCalls = 0;

  @override
  Future<LocalAiModelStatus> getStatus() async => _releasedStatus;

  @override
  Future<LocalAiModelStatus> loadModel() {
    loadCalls += 1;
    return loadResult.future;
  }

  @override
  Future<LocalAiModelStatus> importModel() {
    importCalls += 1;
    return importResult.future;
  }
}


class _ModelControlFailureService extends _TextSendService {
  var resetCalls = 0;
  var releaseCalls = 0;

  @override
  Future<LocalAiModelStatus> resetConversation() async {
    resetCalls += 1;
    throw PlatformException(
      code: 'RESET_FAILED',
      message: '模拟会话重置失败',
    );
  }

  @override
  Future<LocalAiModelStatus> releaseModel() async {
    releaseCalls += 1;
    throw PlatformException(
      code: 'RELEASE_FAILED',
      message: '模拟模型释放失败',
    );
  }
}

class _ModelControlTeardownFailureService extends _TextSendService {
  var resetCalls = 0;
  var releaseCalls = 0;
  var _status = _readyStatus;

  @override
  Future<LocalAiModelStatus> getStatus() async => _status;

  @override
  Future<LocalAiModelStatus> resetConversation() async {
    resetCalls += 1;
    _status = _releasedStatus;
    throw PlatformException(
      code: 'RESET_FAILED_AFTER_TEARDOWN',
      message: '模拟会话重置失败',
    );
  }

  @override
  Future<LocalAiModelStatus> releaseModel() async {
    releaseCalls += 1;
    _status = _releasedStatus;
    throw PlatformException(
      code: 'RELEASE_FAILED_AFTER_TEARDOWN',
      message: '模拟模型释放失败',
    );
  }
}

class _UnknownStatusAfterResetService extends _TextSendService {
  var resetCalls = 0;
  var statusCalls = 0;
  var _statusUnavailable = false;
  var _recoveredNotReady = false;

  @override
  Future<LocalAiModelStatus> getStatus() async {
    statusCalls += 1;
    if (_statusUnavailable) {
      throw StateError('模拟原生状态接口暂不可用');
    }
    return _recoveredNotReady ? _releasedStatus : _readyStatus;
  }

  @override
  Future<LocalAiModelStatus> resetConversation() async {
    resetCalls += 1;
    _statusUnavailable = true;
    throw PlatformException(
      code: 'RESET_FAILED_STATUS_UNKNOWN',
      message: '模拟会话重置失败',
    );
  }

  void recoverAsNotReady() {
    _statusUnavailable = false;
    _recoveredNotReady = true;
  }
}

class _PostSendStatusFailureService extends _TextSendService {
  _PostSendStatusFailureService({this.failSend = false});

  final bool failSend;
  var _statusUnavailable = false;

  @override
  Future<LocalAiModelStatus> getStatus() async {
    if (_statusUnavailable) {
      throw StateError('模拟推理后原生状态接口暂不可用');
    }
    return _readyStatus;
  }

  @override
  Future<String> sendMessage(String text) async {
    sentTexts.add(text);
    _statusUnavailable = true;
    if (failSend) {
      throw PlatformException(
        code: 'INFERENCE_FAILED',
        message: '模拟本地推理失败',
      );
    }
    return '本轮回复：$text';
  }

  void recoverAsReady() {
    _statusUnavailable = false;
  }
}

class _PostSendNotReadyStatusService extends _TextSendService {
  _PostSendNotReadyStatusService({required this.failOnTrigger});

  final bool failOnTrigger;
  static const triggerText = '触发原生模型卸载的本轮输入';
  var _notReady = false;

  @override
  Future<LocalAiModelStatus> getStatus() async =>
      _notReady ? _releasedStatus : _readyStatus;

  @override
  Future<LocalAiModelStatus> loadModel() async {
    _notReady = false;
    return _readyStatus;
  }

  @override
  Future<String> sendMessage(String text) async {
    sentTexts.add(text);
    if (text == triggerText) {
      _notReady = true;
      if (failOnTrigger) {
        throw PlatformException(
          code: 'INFERENCE_FAILED_AFTER_TEARDOWN',
          message: '模拟模型卸载前推理失败',
        );
      }
      return '模型卸载前生成的回复';
    }
    return '历史回复：$text';
  }
}

class _ModelControlService extends _TextSendService {
  var resetCalls = 0;
  var releaseCalls = 0;

  @override
  Future<LocalAiModelStatus> resetConversation() async {
    resetCalls += 1;
    return _readyStatus;
  }

  @override
  Future<LocalAiModelStatus> releaseModel() async {
    releaseCalls += 1;
    return _releasedStatus;
  }
}

class _DraftTextService extends _TextSendService {
  var extractionCalls = 0;

  @override
  Future<LocalAiSymptomDraft> extractSymptoms() async {
    extractionCalls += 1;
    return const LocalAiSymptomDraft(
      mainComplaint: '饭后腹胀',
      duration: '约两周',
      unknowns: ['是否与某种食物有关'],
    );
  }
}

class _InterviewHandoffHost extends StatefulWidget {
  const _InterviewHandoffHost({required this.service});

  final LocalAiService service;

  @override
  State<_InterviewHandoffHost> createState() => _InterviewHandoffHostState();
}

class _InterviewHandoffHostState extends State<_InterviewHandoffHost> {
  String? returnedSummary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              final summary = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => LocalAiInterviewScreen(conversationStore: _store, service: widget.service),
                ),
              );
              if (!mounted || summary == null) return;
              setState(() => returnedSummary = summary);
            },
            child: const Text('打开本地问诊'),
          ),
          if (returnedSummary != null)
            Text(returnedSummary!, key: const ValueKey('returned-summary')),
        ],
      ),
    );
  }
}



class _DelayedHistoryConversationStore extends _MemoryConversationStore {
  final Completer<void> firstReadGate = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> getAssistantMessages({
    required int conversationId,
  }) async {
    if (conversationId == 1) await firstReadGate.future;
    return super.getAssistantMessages(conversationId: conversationId);
  }
}

class _FailOnceTextSendService extends LocalAiService {
  var sendAttempts = 0;

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

  @override
  Future<String> sendMessage(String text) async {
    sendAttempts += 1;
    if (sendAttempts == 1) {
      throw PlatformException(
        code: 'NATIVE_ERROR',
        message: '首次本地推理失败',
      );
    }
    return '重试成功：$text';
  }

  @override
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
  }) => sendMessage(text);
}

class _TraceFailOnceTextSendService extends _FailOnceTextSendService {
  final sentTraceIds = <String>[];

  @override
  Future<String> sendMessageWithTrace(
    String text, {
    required String traceId,
  }) {
    sentTraceIds.add(traceId);
    return sendMessage(text);
  }

  @override
  Future<String> sendMessageWithContextAndTrace(
    String text, {
    required String context,
    required String traceId,
  }) {
    sentTraceIds.add(traceId);
    return sendMessage(text);
  }
}

class _UnexpectedStatusFailureService extends LocalAiService {
  @override
  Future<LocalAiModelStatus> getStatus() async {
    throw StateError('status response was malformed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    _store = _MemoryConversationStore();
  });
  const imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(imagePickerChannel, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(imagePickerChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  testWidgets(
    're-enables stop after a recorder stop failure and accepts a successful retry',
    (tester) async {
      final service = _TextSendService();
      final recorder = _FailOnceStopRecorder();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return '/tmp';
          throw MissingPluginException('Unexpected path provider call: ${call.method}');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(
            conversationStore: _store,
            service: service,
            audioRecorder: recorder,
            recordingFileInspector: _ValidRecordingFileInspector(),
            attachmentStore: _FakeRecordingAttachmentStore('/tmp/local_ai_test.wav'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('录制语音（最长 30 秒）'));
      await _pumpUntilFound(tester, find.byTooltip('停止录音'));
      expect(recorder._path, isNotNull);

      await tester.tap(find.byTooltip('停止录音'));
      await _pumpUntilFound(
        tester,
        find.textContaining('录音停止失败，录音可能仍在继续'),
      );

      expect(recorder.stopCalls, 1);
      expect(find.byTooltip('停止录音'), findsOneWidget);

      await tester.tap(find.byTooltip('停止录音'));
      await _pumpUntilFound(
        tester,
        find.text('语音已录制（最长 30 秒），发送前可移除。'),
      );

      expect(recorder.stopCalls, 2);
      expect(find.textContaining('录音停止失败'), findsNothing);

    },
  );

  testWidgets(
    'reports a stopped recorder when post-stop file inspection fails',
    (tester) async {
      final recorder = _FailOnceStopRecorder(failFirstStop: false);
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getTemporaryDirectory') return '/tmp';
          throw MissingPluginException('Unexpected path provider call: ${call.method}');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(conversationStore: _store, 
            service: _TextSendService(),
            audioRecorder: recorder,
            recordingFileInspector: _ThrowingRecordingFileInspector(),
            attachmentStore: _FakeRecordingAttachmentStore(
              '/tmp/local_ai_inspection_failure.wav',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('录制语音（最长 30 秒）'));
      await _pumpUntilFound(tester, find.byTooltip('停止录音'));
      await tester.tap(find.byTooltip('停止录音'));
      await _pumpUntilFound(
        tester,
        find.textContaining('录音已停止，但读取录音文件失败'),
      );

      expect(recorder.stopCalls, 1);
      expect(find.textContaining('录音已停止，但读取录音文件失败'), findsOneWidget);
      expect(find.byTooltip('录制语音（最长 30 秒）'), findsOneWidget);
      expect(find.byTooltip('停止录音'), findsNothing);
      expect(find.text('语音已录制（最长 30 秒），发送前可移除。'), findsNothing);
    },
  );
  testWidgets(
    'sends a text interview turn and renders the local reply',
    (tester) async {
      final service = _TextSendService();

      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(conversationStore: _store, service: service),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        '我最近三天偶尔头痛，睡眠后会缓解。',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sentTexts, ['我最近三天偶尔头痛，睡眠后会缓解。']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == '已收到你的描述：我最近三天偶尔头痛，睡眠后会缓解。',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('规则辨证问题和答案留在统一助手时间线并持久化', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final state = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'temperature',
    );
    expect(state, isNotNull, reason: '规则问诊启动后必须持久化任务快照；created=${_store._conversations.keys.toList()}，createCalls=${_store.createConversationCalls}，taskWrites=${_store.taskStateSaveCalls}，stateIds=${_store._taskStates.keys.toList()}');
    final savedState = state!;
    expect(savedState.status, 'in_progress');
    expect(savedState.pendingPromptId, 'temperature');
    expect(savedState.pendingPromptText, contains('寒热感觉'));
    expect(
      savedState.transcript.any((message) => message.text.contains('开始规则问诊')),
      isTrue,
    );
    expect(service.sentTexts, isEmpty);

    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text(savedState.pendingOptions.first).last);
    await tester.pumpAndSettle();

    final afterTemperature = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'tongue_pulse',
    );
    expect(afterTemperature, isNotNull, reason: '寒热答案提交后必须持久化任务快照');
    final savedAfterTemperature = afterTemperature!;
    expect(savedAfterTemperature.pendingPromptId, 'tongue_pulse');
    expect(savedAfterTemperature.pendingPromptText, contains('舌象和脉象'));

    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过，直接问诊').last);
    await tester.pumpAndSettle();

    final afterSkip = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'ten:',
      expectedPromptIdStartsWith: true,
    );
    expect(afterSkip, isNotNull, reason: '跳过舌脉后必须持久化问诊进度');
    final savedAfterSkip = afterSkip!;
    expect(savedAfterSkip.pendingPromptId, startsWith('ten:'));
    expect(service.sentTexts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('规则引擎完成且消息与任务快照持久化后自动由 AI 解释结果',
      (tester) async {
    final adapter = TcmInterviewAdapter();
    adapter.answerTemperature('fever_chills');
    adapter.answerTonguePulse(
      tongueCoating: '薄白',
      tongueShape: '淡白',
      primaryPulse: '数',
    );
    adapter.answerFollowUp('pulse_cross_drink', '口渴，喜热饮');
    adapter.answerFollowUp('pulse_cross_urine', '清长色淡');
    final pending = adapter.pulseTongueCrossChecks.singleWhere(
      (prompt) => prompt.id == 'pulse_cross_limbs',
    );

    const taskId = 'verified-diagnosis-auto-interpretation';
    final taskState = TcmInterviewTaskState(
      taskId: taskId,
      snapshot: adapter.createSnapshot(),
      status: 'in_progress',
      pendingPromptId: 'followup:${pending.id}',
      pendingPromptText: pending.question,
      pendingOptions: pending.options,
      transcript: [
        const TcmInterviewTaskMessage(
          text: '开始规则问诊',
          isUser: true,
        ),
        TcmInterviewTaskMessage(
          text: pending.question,
          isUser: false,
        ),
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    final store = _MemoryConversationStore();
    final conversationId = await store.createAssistantConversation(
      title: '待完成的规则问诊',
      mode: 'unified',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'user',
      content: '开始规则问诊',
      metadata: const AssistantMessageMetadata(
        mode: 'consultation',
        tcmTaskId: taskId,
        replayable: true,
      ).encode(),
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: pending.question,
      metadata: const AssistantMessageMetadata(
        mode: 'consultation',
        tcmTaskId: taskId,
        replayable: false,
      ).encode(),
    );
    await store.saveTcmInterviewTaskState(
      conversationId: conversationId,
      state: taskState,
    );

    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待完成的规则问诊'));
    await tester.pumpAndSettle();

    expect(service.sentTexts, isEmpty,
        reason: '恢复未完成问诊不应把尚未完成的内容交给 AI 作为诊断结果');
    final finalAnswer = find.text('偏冷').last;
    await tester.ensureVisible(finalAnswer);
    await tester.tap(finalAnswer);
    await tester.pumpAndSettle();

    final completedState = await store.getTcmInterviewTaskState(
      conversationId: conversationId,
    );
    expect(completedState?.status, 'completed');
    expect(
      completedState?.completedDiagnosis,
      isNotNull,
      reason: '解释触发前必须先得到 DiagnosticEngine 的真实结构化结果',
    );
    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('总结并解释'));
    expect(service.sentTexts.single, contains('六经'));
    expect(service.sentTexts.single, contains('不要生成个体处方、药物或剂量建议'));
    expect(service.sentContexts.single, contains('当前角色：问诊助手'));
    expect(
      find.textContaining('已收到你的描述：'),
      findsOneWidget,
    );

    final savedMessages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    final interpretation = AssistantMessageMetadata.decode(
      savedMessages.last['metadata'] as String,
    );
    expect(savedMessages.last['role'], 'assistant');
    expect(interpretation.toolId, 'structured_diagnosis');
    expect(interpretation.toolStatus, 'SUCCEEDED');
    expect(
      interpretation.sourceIds,
      contains('local-engine:diagnostic-engine'),
    );
    expect(interpretation.traceId, isNull,
        reason: 'TRACE 默认关闭时不生成 trace_id');
    expect(tester.takeException(), isNull);
  });

  testWidgets('结构化问诊批量消息保存失败时不留半轮并标记 persistence FAILED',
      (tester) async {
    const traceId = '61616161616161616161616161616161';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 15),
    );
    _store.failNextMessageBatch = true;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: _TextSendService(),
          imagePicker: _EmptyLocalAiImagePicker(),
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final conversationId = _store._conversations.keys.single;
    expect(_store._messages[conversationId], isEmpty);
    expect(_store._taskStates[conversationId]?.pendingPromptId, 'temperature');
    expect(
      find.text('规则问诊消息未能完整保存，当前页面仍保留内容；历史记录可能不完整，请核实后再继续。'),
      findsOneWidget,
    );
    final persistence = events
        .where((event) =>
            event.traceId == traceId &&
            event.stage == AiTraceStage.persistence)
        .single;
    expect(persistence.status, AiTraceStatus.failed);
    expect(persistence.errorCode, 'PERSISTENCE_FAILED');
    final persistedState = events
        .where((event) =>
            event.traceId == traceId &&
            event.stage == AiTraceStage.persistedState)
        .single;
    expect(persistedState.status, AiTraceStatus.succeeded);
    expect(
      events
          .where((event) =>
              event.traceId == traceId &&
              event.stage == AiTraceStage.finalRender)
          .single
          .status,
      AiTraceStatus.succeeded,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('结构化问诊消息已保存但任务快照失败时分别标记 persistence 和 persistedState',
      (tester) async {
    const traceId = '62626262626262626262626262626262';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 16),
    );
    _store.failNextTaskStateSave = true;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: _TextSendService(),
          imagePicker: _EmptyLocalAiImagePicker(),
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final conversationId = _store._conversations.keys.single;
    expect(_store._messages[conversationId], isNotEmpty);
    expect(_store._messages[conversationId]!.first['content'], '开始规则问诊');
    expect(_store._taskStates[conversationId], isNull);
    expect(
      find.text('问诊消息已保存，但进度快照保存失败；重新进入历史记录时可能无法恢复到当前步骤，请核实后再继续。'),
      findsOneWidget,
    );

    final persistence = events
        .where((event) =>
            event.traceId == traceId &&
            event.stage == AiTraceStage.persistence)
        .single;
    expect(persistence.status, AiTraceStatus.succeeded);
    expect(persistence.errorCode, isNull);

    final persistedState = events
        .where((event) =>
            event.traceId == traceId &&
            event.stage == AiTraceStage.persistedState)
        .single;
    expect(persistedState.status, AiTraceStatus.failed);
    expect(persistedState.errorCode, 'TASK_STATE_PERSISTENCE_FAILED');
    expect(
      events
          .where((event) =>
              event.traceId == traceId &&
              event.stage == AiTraceStage.finalRender)
          .single
          .status,
      AiTraceStatus.succeeded,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('结构化问诊启动与每次选项回答分别关联 TRACE 和消息 metadata',
      (tester) async {
    const startTraceId = '11111111111111111111111111111111';
    const answerTraceId = '22222222222222222222222222222222';
    final traceIds = [startTraceId, answerTraceId];
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceIds.removeAt(0),
      clock: () => DateTime(2026, 11, 12, 15),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: _TextSendService(),
          imagePicker: _EmptyLocalAiImagePicker(),
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final initial = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'temperature',
    );
    expect(initial, isNotNull);
    final conversation = (await _store.getAssistantConversations()).single;
    final initialMessages = await _store.getAssistantMessages(
      conversationId: conversation['id'] as int,
    );
    expect(initialMessages, isNotEmpty);
    expect(
      initialMessages.every(
        (message) =>
            AssistantMessageMetadata.decode(
              message['metadata'] as String,
            ).traceId ==
            startTraceId,
      ),
      isTrue,
    );

    await tester.tap(find.text('发热 + 怕冷').last);
    await tester.pumpAndSettle();
    final afterAnswer = await _waitForTcmInterviewTaskState(
      tester,
      conversationId: conversation['id'] as int,
      expectedPendingPromptId: 'tongue_pulse',
    );
    expect(afterAnswer, isNotNull);

    final allMessages = await _store.getAssistantMessages(
      conversationId: conversation['id'] as int,
    );
    expect(
      allMessages.skip(initialMessages.length).every(
        (message) =>
            AssistantMessageMetadata.decode(
              message['metadata'] as String,
            ).traceId ==
            answerTraceId,
      ),
      isTrue,
    );
    for (final traceId in [startTraceId, answerTraceId]) {
      final stages = events
          .where((event) => event.traceId == traceId)
          .map((event) => event.stage);
      expect(stages, containsAll([
        AiTraceStage.input,
        AiTraceStage.route,
        AiTraceStage.dispatch,
        AiTraceStage.businessExecution,
        AiTraceStage.persistence,
        AiTraceStage.persistedState,
        AiTraceStage.presentation,
        AiTraceStage.finalRender,
      ]));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('问诊进行中可独立查看只读脏腑证据，不等待辨证结果', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final initialState = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'temperature',
    );
    expect(initialState, isNotNull);
    await tester.tap(find.text('发热 + 怕冷').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('问诊证据'));
    await tester.pumpAndSettle();

    expect(find.text('脏腑证据（只读）'), findsOneWidget);
    expect(find.text('寒热辨经'), findsOneWidget);
    expect(find.text('发热 + 怕冷'), findsWidgets);
    expect(find.textContaining('脏腑归属：MISSING'), findsOneWidget);
    expect(
      find.textContaining('不进行脏腑归属、诊断或方剂计算'),
      findsOneWidget,
    );
    expect(find.text('辨证结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一对话舌脉输入将主脉与兼脉写入引擎快照', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final initialState = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'temperature',
    );
    expect(initialState, isNotNull, reason: '舌脉 UI 测试未找到初始快照；created=${_store._conversations.keys.toList()}，createCalls=${_store.createConversationCalls}，taskWrites=${_store.taskStateSaveCalls}，stateIds=${_store._taskStates.keys.toList()}');
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text(initialState!.pendingOptions.first).last);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择舌诊脉诊').last);
    await tester.pumpAndSettle();

    // 主脉浮不与薄白/淡白舌象触发该冲突；由兼脉数单独触发，
    // 用于验证 UI → SQLite 快照 → DiagnosticEngine 的真实输入链。
    await tester.tap(find.text('薄白').last);
    await tester.tap(find.text('淡白').last);
    await tester.tap(find.widgetWithText(FilterChip, '浮').first);
    await tester.pumpAndSettle();
    final secondaryPulseChip = find.widgetWithText(FilterChip, '数').last;
    await tester.tap(secondaryPulseChip);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(secondaryPulseChip).selected, isTrue);
    await tester.tap(find.text('确认').last);
    await tester.pumpAndSettle();

    final savedState = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'ten:',
      expectedPromptIdStartsWith: true,
    );
    expect(savedState, isNotNull);
    expect(savedState!.snapshot.tongueCoating, '薄白');
    expect(savedState.snapshot.tongueShape, '淡白');
    expect(savedState.snapshot.pulseType, '浮');
    expect(savedState.snapshot.pulseTypeSecondary, '数');

    final restoredEngine = DiagnosticEngine()
      ..restoreSnapshot(savedState.snapshot);
    final engineFollowUpKeys = restoredEngine
        .getPulseTongueFollowUpQuestions()
        .map((question) => question.key)
        .toSet();
    expect(
      engineFollowUpKeys,
      containsAll(['pulse_cross_drink', 'pulse_cross_urine', 'pulse_cross_limbs']),
      reason: '兼脉数应从统一对话 UI 经持久化快照进入引擎交叉核验',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一问诊完成十问后仍会追问尚未核实的脉舌少阳冲突', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tapOption(String option) async {
      final lists = find.byType(ListView);
      if (lists.evaluate().isNotEmpty) {
        await tester.drag(lists.last, const Offset(0, -700));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    Future<TcmInterviewTaskState?> waitForPromptChange(
      String previousPromptId,
    ) async {
      for (var attempt = 0; attempt < 40; attempt++) {
        final ids = _store._conversations.keys.toList(growable: false).reversed;
        for (final id in ids) {
          final candidate =
              await _store.getTcmInterviewTaskState(conversationId: id);
          if (candidate != null &&
              candidate.pendingPromptId != previousPromptId) {
            return candidate;
          }
        }
        await tester.pump(const Duration(milliseconds: 10));
      }
      return null;
    }

    await tester.enterText(find.byType(TextField), '开始规则问诊');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final initial = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'temperature',
    );
    expect(initial, isNotNull);
    await tapOption('发热 + 怕冷');

    final tonguePrompt = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'tongue_pulse',
    );
    expect(tonguePrompt, isNotNull);
    await tapOption('选择舌诊脉诊');
    await tester.tap(find.text('白厚').last);
    await tester.tap(find.text('淡白').last);
    await tester.tap(find.widgetWithText(FilterChip, '弦').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认').last);
    await tester.pumpAndSettle();

    var state = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'ten:',
      expectedPromptIdStartsWith: true,
    );
    expect(state, isNotNull);
    var answeredTenQuestions = 0;
    while (state!.pendingPromptId?.startsWith('ten:') == true) {
      final promptId = state.pendingPromptId!;
      final questionId = promptId.substring('ten:'.length);
      final option = switch (questionId) {
        'gender' => '男',
        'temperature' => '手脚冰冷（阴·阳虚）',
        'pulse' => '没摸过/不清楚',
        _ => state.pendingOptions.first,
      };
      expect(state.pendingOptions, contains(option), reason: promptId);
      await tapOption(option);
      final next = await waitForPromptChange(promptId);
      expect(next, isNotNull, reason: '问诊没有离开 $promptId');
      state = next;
      answeredTenQuestions += 1;
      expect(answeredTenQuestions, lessThanOrEqualTo(12));
    }

    expect(state.pendingPromptId, 'zhenjia');
    await tapOption('没有/跳过');

    final conflictPrompt = await _waitForTcmInterviewTaskState(
      tester,
      expectedPendingPromptId: 'followup:pulse_cross_shaoyang',
    );
    expect(conflictPrompt, isNotNull);
    expect(
      conflictPrompt!.transcript.any(
        (message) => message.text.contains('少阳相关问诊线索'),
      ),
      isTrue,
    );

    await tapOption('不清楚');
    TcmInterviewTaskState? completed;
    for (var attempt = 0; attempt < 40; attempt++) {
      for (final id in _store._conversations.keys.toList(growable: false)) {
        final candidate =
            await _store.getTcmInterviewTaskState(conversationId: id);
        if (candidate?.status == 'completed') {
          completed = candidate;
          break;
        }
      }
      if (completed != null) break;
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(completed, isNotNull);
    expect(
      completed!.snapshot.answers['pulse_cross_shaoyang_answered'],
      isTrue,
    );
    expect(completed.snapshot.answers['dry_throat'], isNull);
    expect(completed.completedDiagnosis, isNotNull);
    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('总结并解释'));
    expect(service.sentTexts.single, contains('不重新辨证'));
    expect(
      service.sentContexts.single,
      contains('当前角色：问诊助手'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('问诊助手把本地中医知识作为参考上下文传给模型', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(conversationStore: _store, 
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我最近三天口苦，胸闷');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTexts, ['我最近三天口苦，胸闷']);
    expect(service.sentContexts, hasLength(1));
    expect(service.sentContexts.single, contains('当前角色：问诊助手'));
    expect(service.sentContexts.single, contains('App 本地知识库'));
    expect(service.sentContexts.single, contains('不独立作个体诊断'));
    expect(service.sentContexts.single, contains('解释和归纳已有结果'));
    expect(service.sentContexts.single, contains('必须区分规则输出、知识来源与 AI 解释'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'warns the user when symptom source history was truncated',
    (tester) async {
      final service = _SourceTruncatedSymptomsService();

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我较早的头痛描述');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('整理本次症状'));
      await tester.pumpAndSettle();

      expect(find.text('记录范围不完整：较早或超长的输入可能未包含在本次整理中。请补充遗漏内容并逐项核对，不要把未显示的信息理解为你没有相关症状。'), findsOneWidget);
      expect(find.text('确认这份整理'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认这份整理'));
      await tester.pumpAndSettle();

      expect(find.text('已核对的用户自述'), findsOneWidget);
      expect(find.text('记录范围不完整：较早或超长的输入可能未包含在本次整理中。请补充遗漏内容并逐项核对，不要把未显示的信息理解为你没有相关症状。'), findsOneWidget);
    },
  );
  testWidgets(
    'explains missing draft when the source history was truncated',
    (tester) async {
      final service = _SourceTruncatedEmptySymptomsService();

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '此前描述过的症状');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('整理本次症状'));
      await tester.pumpAndSettle();

      expect(
        find.text('原始输入记录曾被裁剪，但本次未提取到可核对内容。请补充遗漏描述后重新整理。'),
        findsOneWidget,
      );
      expect(find.text('核对症状整理'), findsNothing);
    },
  );
  testWidgets(
    'reset conversation clears prior turns and keeps the model loaded',
    (tester) async {
      final service = _ModelControlService();
      const userText = '上一轮问诊内容';

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == '已收到你的描述：$userText',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('重新开始对话'));
      await tester.pumpAndSettle();

      expect(service.resetCalls, 1);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == '已收到你的描述：$userText',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == '我们重新开始。先说说这次最想了解的身体情况。',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('释放模型内存'), findsOneWidget);
    },
  );

  testWidgets(
    'release model clears prior turns and returns the UI to the unloaded state',
    (tester) async {
      final service = _ModelControlService();
      const userText = '本轮不再保留的内容';

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('释放模型内存'));
      await tester.pumpAndSettle();

      expect(service.releaseCalls, 1);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == '模型已释放，设备内存已归还。再次使用时可重新加载。',
        ),
        findsOneWidget,
      );
      expect(find.text('模型已放入设备，尚未加载'), findsOneWidget);
      expect(find.byTooltip('释放模型内存'), findsNothing);
    },
  );

  testWidgets(
    'keeps the active conversation when reset fails and reports the error',
    (tester) async {
      final service = _ModelControlFailureService();
      const userText = '重置失败时应保留的对话';

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('重新开始对话'));
      await tester.pumpAndSettle();

      expect(service.resetCalls, 1);
      expect(find.text('模拟会话重置失败'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('重新开始对话'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps the active model state when release fails and reports the error',
    (tester) async {
      final service = _ModelControlFailureService();
      const userText = '释放失败时应保留的对话';

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('释放模型内存'));
      await tester.pumpAndSettle();

      expect(service.releaseCalls, 1);
      expect(find.text('模拟模型释放失败'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('释放模型内存'), findsOneWidget);
    },
  );

  testWidgets(
    'clears stale conversation when reset fails after native teardown',
    (tester) async {
      final service = _ModelControlTeardownFailureService();
      const userText = '原生会话失效后不应继续显示的历史';

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining(userText), findsWidgets);

      await tester.tap(find.byTooltip('重新开始对话'));
      await tester.pumpAndSettle();

      expect(service.resetCalls, 1);
      expect(find.text('模拟会话重置失败'), findsOneWidget);
      expect(find.textContaining(userText), findsNothing);
      expect(
        find.text('会话重置失败，原生会话已关闭。请重新加载模型后重新开始。'),
        findsOneWidget,
      );
      expect(find.byTooltip('重新开始对话'), findsNothing);
      expect(find.byTooltip('释放模型内存'), findsNothing);
    },
  );

  testWidgets(
    'clears stale conversation when release fails after native teardown',
    (tester) async {
      final service = _ModelControlTeardownFailureService();
      const userText = '模型释放后不应继续显示的历史';

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining(userText), findsWidgets);

      await tester.tap(find.byTooltip('释放模型内存'));
      await tester.pumpAndSettle();

      expect(service.releaseCalls, 1);
      expect(find.text('模拟模型释放失败'), findsOneWidget);
      expect(find.textContaining(userText), findsNothing);
      expect(
        find.text('释放操作发生错误，但原生模型运行态已清空。重新加载后可继续使用。'),
        findsOneWidget,
      );
      expect(find.byTooltip('释放模型内存'), findsNothing);
    },
  );
  testWidgets(
    'disables local AI actions when native status cannot be verified',
    (tester) async {
      final service = _UnknownStatusAfterResetService();
      const userText = '状态未知时必须保留但不能继续使用的历史';

      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(conversationStore: _store, 
            service: service,
            imagePicker: _EmptyLocalAiImagePicker(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 首次模型状态查询是异步的；必须等到 ready UI 出现后再发送，
      // 否则测试可能只触发“模型未加载”的提示，根本没有执行 sendMessage。
      for (var attempt = 0;
          attempt < 50 && find.byTooltip('释放模型内存').evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byTooltip('释放模型内存'), findsOneWidget);
      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      final sendButton = find.ancestor(
        of: find.byTooltip('发送'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      // 等待本轮推理、持久化和发送后的原生状态回读完成，避免在异步窗口内
      // 点击被忙碌锁禁用的重置按钮。
      for (var attempt = 0;
          attempt < 50 &&
              (!service.sentTexts.contains(userText) || service.statusCalls < 2);
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(service.sentTexts, contains(userText));
      expect(service.statusCalls, greaterThanOrEqualTo(2));

      await tester.tap(find.byTooltip('重新开始对话'));
      await tester.pumpAndSettle();

      expect(service.resetCalls, 1);
      expect(find.text('无法确认本地模型状态'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('选择并导入模型文件'), findsNothing);
      expect(find.text('重新检查状态'), findsOneWidget);

      service.recoverAsNotReady();
      await tester.tap(find.text('重新检查状态'));
      await tester.pumpAndSettle();

      expect(find.text('无法确认本地模型状态'), findsNothing);
      expect(find.textContaining(userText), findsNothing);
      expect(
        find.text('已确认原生模型当前未就绪。此前会话已结束，重新加载模型后可开始新对话。'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    },
  );

  group('post-send native status readback', () {
    testWidgets(
      'blocks follow-up messages when status readback fails after a successful reply',
      (tester) async {
        final service = _PostSendStatusFailureService();
        const userText = '推理成功后状态回读失败时应保留的输入';
        const replyText = '本轮回复：$userText';

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), userText);
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        expect(service.sentTexts, [userText]);
        expect(find.text('无法确认本地模型状态'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == userText,
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == replyText,
          ),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(find.text('选择并导入模型文件'), findsNothing);

        service.recoverAsReady();
        await tester.tap(find.text('重新检查状态'));
        await tester.pumpAndSettle();

        expect(find.text('无法确认本地模型状态'), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == replyText,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'keeps failed input editable after status readback fails',
      (tester) async {
        final service = _PostSendStatusFailureService(failSend: true);
        const userText = '推理失败后需要保留供重试的输入';

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), userText);
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        expect(service.sentTexts, [userText]);
        expect(find.text('无法确认本地模型状态'), findsOneWidget);
        expect(find.textContaining('模拟本地推理失败'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == userText,
          ),
          findsNothing,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          userText,
        );
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

        service.recoverAsReady();
        await tester.tap(find.text('重新检查状态'));
        await tester.pumpAndSettle();

        expect(find.text('无法确认本地模型状态'), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          userText,
        );
      },
    );
  });

  group('post-send native model teardown', () {
    testWidgets(
      'keeps only the completed reply when status confirms model unloaded',
      (tester) async {
        final service = _PostSendNotReadyStatusService(failOnTrigger: false);
        const oldText = '此前会话中的旧输入';

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), oldText);
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          _PostSendNotReadyStatusService.triggerText,
        );
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            '本轮回复已生成，但原生模型已变为未加载状态。旧会话已结束；以下回复仅供查看，重新加载后请开始新对话。',
          ),
          findsOneWidget,
        );
        expect(find.text('模型卸载前生成的回复'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == oldText,
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.data == _PostSendNotReadyStatusService.triggerText,
          ),
          findsNothing,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );

        await tester.tap(find.text('加载本地模型'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        expect(find.text(oldText), findsNothing);
        expect(find.text('模型卸载前生成的回复'), findsOneWidget);
      },
    );

    testWidgets(
      'clears old chat but preserves failed input when status confirms model unloaded',
      (tester) async {
        final service = _PostSendNotReadyStatusService(failOnTrigger: true);
        const oldText = '失败前的历史会话';

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), oldText);
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          _PostSendNotReadyStatusService.triggerText,
        );
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await tester.pumpAndSettle();

        expect(find.text('模型已放入设备，尚未加载'), findsOneWidget);
        expect(
          find.text(
            '本地模型已变为未加载状态，旧会话已结束。编辑框中的内容和附件仍保留；重新加载后可重新发送。',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('模拟模型卸载前推理失败'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == oldText,
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.data == _PostSendNotReadyStatusService.triggerText,
          ),
          findsNothing,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          _PostSendNotReadyStatusService.triggerText,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );

        await tester.tap(find.text('加载本地模型'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          _PostSendNotReadyStatusService.triggerText,
        );
        expect(find.text(oldText), findsNothing);
      },
    );
  });

  testWidgets(
    'returns symptom summary to rule interview only after explicit confirmation',
    (tester) async {
      final service = _DraftTextService();

      await tester.pumpWidget(
        MaterialApp(home: _InterviewHandoffHost(service: service)),
      );

      await tester.tap(find.text('打开本地问诊'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '我饭后腹胀，已经持续约两周。');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sentTexts, ['我饭后腹胀，已经持续约两周。']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('整理本次症状'), findsOneWidget);
      await tester.tap(find.text('整理本次症状'));
      await tester.pumpAndSettle();

      expect(service.extractionCalls, 1);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data == '目前没有提取到明确的自述信息，请补充描述后再整理。',
        ),
        findsNothing,
      );
      expect(find.text('核对症状整理'), findsOneWidget);
      expect(find.text('确认这份整理'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('确认这份整理'));
      await tester.pumpAndSettle();

      expect(find.text('已核对的用户自述'), findsOneWidget);
      await tester.tap(find.text('继续规则辨证'));
      await tester.pumpAndSettle();

      // 已确认自述直接进入当前消息时间线；自由文本只作上下文，
      // 不会被模型或控制器自动转换为规则答案。
      expect(find.byType(LocalAiInterviewScreen), findsOneWidget);
      final taskState = await _waitForTcmInterviewTaskState(
        tester,
        expectedPendingPromptId: 'temperature',
      );
      expect(taskState, isNotNull, reason: '确认症状后启动规则问诊必须持久化任务');
      final savedTaskState = taskState!;
      expect(savedTaskState.pendingPromptId, 'temperature');
      expect(savedTaskState.pendingPromptText, contains('寒热感觉'));
      expect(
        savedTaskState.transcript.any(
          (message) => message.text.contains('主要不适：饭后腹胀'),
        ),
        isTrue,
      );
      expect(
        savedTaskState.transcript.any(
          (message) => message.text.contains('未自动转换为规则答案'),
        ),
        isTrue,
      );
    },
  );



  testWidgets('快速切换历史会话时较早的异步读取不能覆盖较新的选择', (tester) async {
    final store = _DelayedHistoryConversationStore();
    final firstId = await store.createAssistantConversation(title: '较早会话');
    final secondId = await store.createAssistantConversation(title: '较新会话');
    await store.saveAssistantMessage(conversationId: firstId, role: 'user', content: 'FIRST_HISTORY_MARKER');
    await store.saveAssistantMessage(conversationId: secondId, role: 'user', content: 'SECOND_HISTORY_MARKER');

    await tester.pumpWidget(MaterialApp(
      home: LocalAiInterviewScreen(
        conversationStore: store,
        service: _TextSendService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('较早会话'));
    await tester.pump();

    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('较新会话'));
    await tester.pumpAndSettle();
    expect(find.text('SECOND_HISTORY_MARKER'), findsOneWidget);

    store.firstReadGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('SECOND_HISTORY_MARKER'), findsOneWidget);
    expect(find.text('FIRST_HISTORY_MARKER'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps failed text editable and retries without duplicate chat bubbles',
    (tester) async {
      final service = _TraceFailOnceTextSendService();
      // This test exercises transport retry, not symptom routing.
      const userText = '你好';
      const failedTraceId = '44444444444444444444444444444444';
      const retryTraceId = '55555555555555555555555555555555';
      final traceIds = [failedTraceId, retryTraceId];
      final traceEvents = <AiTraceEvent>[];
      final traceRecorder = AiTraceRecorder(
        enabled: true,
        writer: (event) async => traceEvents.add(event),
        idFactory: () => traceIds.removeAt(0),
        clock: () => DateTime(2026, 11, 12, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(
            conversationStore: _store,
            service: service,
            traceRecorder: traceRecorder,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sendAttempts, 1);
      expect(service.sentTraceIds, [failedTraceId]);
      final failedEvents =
          traceEvents.where((event) => event.traceId == failedTraceId).toList();
      expect(
        failedEvents.any(
          (event) =>
              event.stage == AiTraceStage.nativeInference &&
              event.status == AiTraceStatus.unknown,
        ),
        isTrue,
      );
      final failedPersistence = failedEvents.singleWhere(
        (event) => event.stage == AiTraceStage.persistence,
      );
      expect(failedPersistence.status, AiTraceStatus.notStarted);
      expect(failedPersistence.conversationId, isNotNull);
      expect(failedPersistence.errorCode, 'NATIVE_TURN_NOT_PERSISTED');
      expect(find.textContaining('首次本地推理失败'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        userText,
      );

      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sendAttempts, 2);
      expect(service.sentTraceIds, [failedTraceId, retryTraceId]);
      final retryEvents =
          traceEvents.where((event) => event.traceId == retryTraceId).toList();
      expect(
        retryEvents.any(
          (event) =>
              event.stage == AiTraceStage.resultValidation &&
              event.status == AiTraceStatus.succeeded,
        ),
        isTrue,
      );
      expect(
        retryEvents.any(
          (event) =>
              event.stage == AiTraceStage.persistence &&
              event.status == AiTraceStatus.succeeded,
        ),
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == '重试成功：$userText',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == userText,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('首次本地推理失败'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'clears the initial status check and reports unexpected status errors',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(conversationStore: _store, 
            service: _UnexpectedStatusFailureService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('读取本地模型状态失败'), findsOneWidget);
      expect(find.textContaining('status response was malformed'), findsOneWidget);
    },
  );

  group('local AI photo picker lifecycle', () {
    testWidgets(
      'locks attachment-sensitive actions during lost-result recovery and camera selection',
      (tester) async {
        final service = _TextSendService();
        final picker = _DeferredLocalAiImagePicker();
        IconButton iconButton(String tooltip) =>
            tester.widgetList<IconButton>(find.byType(IconButton)).firstWhere(
              (button) => button.tooltip == tooltip,
            );

        await tester.pumpWidget(
          MaterialApp(
            home: LocalAiInterviewScreen(conversationStore: _store, 
              service: service,
              imagePicker: picker,
            ),
          ),
        );
        // Let native status finish while lost-result recovery remains pending.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));

        expect(picker.retrieveCalls, 1);
        expect(find.byTooltip('释放模型内存'), findsOneWidget);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(iconButton('拍摄舌象').onPressed, isNull);
        expect(
          iconButton('录制语音（最长 30 秒）').onPressed,
          isNull,
        );
        expect(iconButton('重新开始对话').onPressed, isNull);
        expect(iconButton('释放模型内存').onPressed, isNull);

        picker.retrieveResult.complete(null);
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
        await tester.enterText(find.byType(TextField), '等待拍照期间必须保留的文字');
        await tester.pump();
        await tester.tap(find.byTooltip('拍摄舌象'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('拍照'));
        await tester.pump();

        expect(picker.pickCalls, 1);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(iconButton('重新开始对话').onPressed, isNull);
        expect(iconButton('释放模型内存').onPressed, isNull);
        expect(
          iconButton('录制语音（最长 30 秒）').onPressed,
          isNull,
        );
        expect(iconButton('发送').onPressed, isNull);

        // Repeated taps cannot launch a second platform picker operation.
        await tester.tap(find.byTooltip('拍摄舌象'), warnIfMissed: false);
        await tester.pump();
        expect(picker.pickCalls, 1);

        picker.pickResult.complete(null);
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '等待拍照期间必须保留的文字',
        );
        expect(iconButton('重新开始对话').onPressed, isNotNull);
        expect(iconButton('释放模型内存').onPressed, isNotNull);
        expect(iconButton('发送').onPressed, isNotNull);
        expect(service.sentTexts, isEmpty);
      },
    );
  });

  group('local AI model control serialization', () {
    testWidgets(
      'makes reset exclusive and blocks session actions until it completes',
      (tester) async {
        final service = _DeferredModelControlService();
        IconButton button(String tooltip) =>
            tester.widgetList<IconButton>(find.byType(IconButton)).firstWhere(
              (item) => item.tooltip == tooltip,
            );

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        final reset = button('重新开始对话').onPressed!;
        final release = button('释放模型内存').onPressed!;
        reset();
        reset();
        release();
        await tester.pump();

        expect(service.resetCalls, 1);
        expect(service.releaseCalls, 0);
        expect(button('重新开始对话').onPressed, isNull);
        expect(button('释放模型内存').onPressed, isNull);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(button('拍摄舌象').onPressed, isNull);
        expect(button('录制语音（最长 30 秒）').onPressed, isNull);
        expect(button('发送').onPressed, isNull);

        service.resetResult.complete(_readyStatus);
        await tester.pumpAndSettle();

        expect(button('重新开始对话').onPressed, isNotNull);
        expect(button('释放模型内存').onPressed, isNotNull);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      },
    );

    testWidgets(
      'makes model release exclusive and blocks session actions until it completes',
      (tester) async {
        final service = _DeferredModelControlService();
        IconButton button(String tooltip) =>
            tester.widgetList<IconButton>(find.byType(IconButton)).firstWhere(
              (item) => item.tooltip == tooltip,
            );

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        final release = button('释放模型内存').onPressed!;
        final reset = button('重新开始对话').onPressed!;
        release();
        release();
        reset();
        await tester.pump();

        expect(service.releaseCalls, 1);
        expect(service.resetCalls, 0);
        expect(button('重新开始对话').onPressed, isNull);
        expect(button('释放模型内存').onPressed, isNull);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(button('拍摄舌象').onPressed, isNull);
        expect(button('录制语音（最长 30 秒）').onPressed, isNull);
        expect(button('发送').onPressed, isNull);

        service.releaseResult.complete(_releasedStatus);
        await tester.pumpAndSettle();

        expect(find.byTooltip('重新开始对话'), findsNothing);
        expect(find.byTooltip('释放模型内存'), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      },
    );
  });

  group('local AI model setup serialization', () {
    testWidgets(
      'keeps model setup controls disabled during lost-photo recovery',
      (tester) async {
        final service = _DeferredModelSetupService();
        final picker = _DeferredLocalAiImagePicker();

        await tester.pumpWidget(
          MaterialApp(
            home: LocalAiInterviewScreen(conversationStore: _store, 
              service: service,
              imagePicker: picker,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));

        expect(picker.retrieveCalls, 1);
        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
          ).onPressed,
          isNull,
        );

        picker.retrieveResult.complete(null);
        await tester.pumpAndSettle();

        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
          ).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'refreshes model hash status after a load-time integrity failure',
      (tester) async {
        final service = _HashVerificationFailureService();

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('模型文件大小与 SHA-256 均已通过校验：3.66 GB。'),
          findsOneWidget,
        );
        final load = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '加载本地模型'),
        ).onPressed!;
        load();
        await tester.pumpAndSettle();

        expect(service.loadCalls, 1);
        expect(service.statusCalls, 2);
        expect(find.text('模型 SHA-256 校验失败，请重新导入'), findsOneWidget);
        expect(
          find.textContaining('首次加载前仍会校验 SHA-256'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'releases model setup lock after a load failure',
      (tester) async {
        final service = _DeferredModelSetupService();

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        final load = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '加载本地模型'),
        ).onPressed!;
        load();
        await tester.pump();
        expect(service.loadCalls, 1);

        service.loadResult.completeError(
          PlatformException(code: 'LOAD_FAILED', message: '模拟模型加载失败'),
        );
        await tester.pumpAndSettle();

        expect(find.text('模拟模型加载失败'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
          ).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'releases model setup lock after an import failure',
      (tester) async {
        final service = _DeferredModelSetupService();

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        final import = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
        ).onPressed!;
        import();
        await tester.pump();
        expect(service.importCalls, 1);

        service.importResult.completeError(
          PlatformException(code: 'IMPORT_FAILED', message: '模拟模型导入失败'),
        );
        await tester.pumpAndSettle();

        expect(find.text('模拟模型导入失败'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
          ).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'makes model loading exclusive and blocks import and session actions',
      (tester) async {
        final service = _DeferredModelSetupService();
        IconButton iconButton(String tooltip) =>
            tester.widgetList<IconButton>(find.byType(IconButton)).firstWhere(
              (button) => button.tooltip == tooltip,
            );

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        final loadButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '加载本地模型'),
        );
        final load = loadButton.onPressed!;
        load();
        load();
        await tester.pump();

        expect(service.loadCalls, 1);
        expect(service.importCalls, 0);
        expect(
          tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
          ).onPressed,
          isNull,
        );
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(iconButton('拍摄舌象').onPressed, isNull);
        expect(iconButton('录制语音（最长 30 秒）').onPressed, isNull);

        service.loadResult.complete(_readyStatus);
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
        expect(find.text('Gemma 4 E4B · CPU'), findsOneWidget);
      },
    );

    testWidgets(
      'makes model import exclusive and blocks load and session actions',
      (tester) async {
        final service = _DeferredModelSetupService();
        IconButton iconButton(String tooltip) =>
            tester.widgetList<IconButton>(find.byType(IconButton)).firstWhere(
              (button) => button.tooltip == tooltip,
            );

        await tester.pumpWidget(
          MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: service)),
        );
        await tester.pumpAndSettle();

        final importButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
        );
        final import = importButton.onPressed!;
        import();
        import();
        await tester.pump();

        expect(service.importCalls, 1);
        expect(service.loadCalls, 0);
        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNull,
        );
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
        expect(iconButton('拍摄舌象').onPressed, isNull);
        expect(iconButton('录制语音（最长 30 秒）').onPressed, isNull);

        service.importResult.complete(_releasedStatus);
        await tester.pumpAndSettle();

        expect(
          tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '加载本地模型'),
          ).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择并导入模型文件'),
          ).onPressed,
          isNotNull,
        );
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      },
    );
  });

  testWidgets('unified assistant starts in automatic dispatch mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LocalAiInterviewScreen(conversationStore: _store, service: _TextSendService())),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动调度'), findsOneWidget);
    expect(
      find.textContaining('身体情况、询问中医知识'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('知识详情传入的初始问题预填统一助手但不会自动发送', (tester) async {
    const prompt = '请介绍太阳病的核心脉证，并标记缺失出处。';
    final service = _TextSendService();

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          initialPrompt: prompt,
          conversationStore: _store,
          service: service,
          imagePicker: _EmptyLocalAiImagePicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, prompt);
    expect(service.sentTexts, isEmpty);
    expect(_store.createConversationCalls, 1);
  });


  testWidgets('统一助手恢复结构化诊断结果后保留收藏、分享和复制处方操作', (tester) async {
    final store = _MemoryConversationStore();
    const resultText = '辨证结果\n【六经】少阳\n【证型】少阳证\n【方剂】小柴胡汤';
    final diagnosis = DiagnosisResult(
      meridian: '少阳',
      pattern: '少阳证',
      formula: '小柴胡汤',
      prescription: const FormulaPrescription(
        formulaName: '小柴胡汤',
        components: [
          PrescriptionComponent(name: '柴胡', dosage: '24g'),
          PrescriptionComponent(name: '黄芩', dosage: '9g'),
        ],
      ),
    );
    final conversationId = await store.createAssistantConversation(
      title: '已完成的结构化辨证',
      mode: 'unified',
    );
    await store.saveAssistantMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: resultText,
    );
    await store.saveTcmInterviewTaskState(
      conversationId: conversationId,
      state: TcmInterviewTaskState(
        taskId: 'completed-diagnosis-actions',
        snapshot: DiagnosticEngine().createSnapshot(),
        status: 'completed',
        transcript: const [
          TcmInterviewTaskMessage(
            text: resultText,
            isUser: false,
            isResult: true,
          ),
        ],
        updatedAt: DateTime.now().toUtc(),
        completedDiagnosis: diagnosis,
      ),
    );

    final bookmarks = <Bookmark>[];
    final sharedTexts = <String>[];
    final copiedTexts = <String>[];
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: store,
          imagePicker: _EmptyLocalAiImagePicker(),
          bookmarkWriter: (bookmark) async {
            bookmarks.add(bookmark);
            return 1;
          },
          shareDiagnosisText: sharedTexts.add,
          copyPrescriptionText: (text) async {
            copiedTexts.add(text);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    expect(find.text('已完成的结构化辨证'), findsOneWidget);
    await tester.tap(find.text('已完成的结构化辨证'));
    await tester.pumpAndSettle();

    expect(service.restoredTranscripts, isNotEmpty);
    expect(service.restoredTranscripts.last, contains('【六经】少阳'));
    expect(service.restoredTranscripts.last, contains('【证型】少阳证'));
    expect(service.restoredTranscripts.last, contains('【方剂】小柴胡汤'));
    expect(find.text('AI解读辨证结果'), findsOneWidget);

    Future<void> tapAction(String label) async {
      final target = find.text(label).last;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(find.text('收藏辨证结果'), findsOneWidget);
    expect(find.text('分享辨证结果'), findsOneWidget);
    expect(find.text('复制处方'), findsOneWidget);

    await tapAction('收藏辨证结果');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.category, '辨证结果');
    expect(bookmarks.single.source, 'chat_diagnosis');
    expect(bookmarks.single.content, contains('小柴胡汤'));

    await tapAction('分享辨证结果');
    expect(sharedTexts, hasLength(1));
    expect(sharedTexts.single, contains('少阳证'));
    expect(sharedTexts.single, contains('柴胡'));

    await tapAction('复制处方');
    expect(copiedTexts, hasLength(1));
    expect(copiedTexts.single, contains('处方: 小柴胡汤'));
    expect(copiedTexts.single, contains('柴胡24g'));

    await tapAction('AI解读辨证结果');
    expect(service.sentTexts.last, contains('总结并解释'));
    expect(service.sentTexts.last, contains('少阳证'));
    expect(service.sentTexts.last, contains('不要生成个体处方、药物或剂量建议'));
    expect(service.sentContexts.last, contains('当前角色：问诊助手'));
    expect(service.restoredTranscripts.last, contains('【方剂】小柴胡汤'));

    final persistedMessages = await store.getAssistantMessages(
      conversationId: conversationId,
    );
    final interpretationMetadata = AssistantMessageMetadata.decode(
      persistedMessages.last['metadata'] as String,
    );
    expect(interpretationMetadata.toolId, 'structured_diagnosis');
    expect(interpretationMetadata.toolStatus, 'SUCCEEDED');
    expect(
      interpretationMetadata.sourceIds,
      contains('local-engine:diagnostic-engine'),
    );
    expect(
      interpretationMetadata.sourceIds.any(
        (sourceId) => sourceId.startsWith('neijing:'),
      ),
      isTrue,
      reason: '保留本轮实际检索到的知识来源，不能只留下引擎来源',
    );
    expect(tester.takeException(), isNull);
  });



  testWidgets('没有明确日期时五运六气仍保留页面确认流程', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我推算五运六气');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTexts, isEmpty);
    expect(find.text('打开五运六气推算'), findsOneWidget);
    expect(find.textContaining('执行结果'), findsNothing);
  });

  testWidgets('五运六气通过 Headless 执行器直接计算并持久化真实参数与来源',
      (tester) async {
    const traceId = 'fedcba9876543210fedcba9876543210';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 14),
    );
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '帮我推算五运六气 2026-11-12',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('自动总结并解释实际输入'));
    expect(find.textContaining('五运六气推算执行结果'), findsOneWidget);
    expect(find.textContaining('推算日期：2026-11-12'), findsOneWidget);
    expect(find.textContaining('丙午年'), findsOneWidget);
    expect(find.text('打开五运六气推算'), findsNothing);

    final conversations = await _store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final messages = await _store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    expect(messages, hasLength(3));
    final resultMessage = messages.firstWhere(
      (message) =>
          (message['content'] as String).contains('五运六气推算执行结果'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'yunqi');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {'date': '2026-11-12'});
    expect(metadata.sourceIds, const ['local-engine:yunqi']);
    expect(metadata.traceId, traceId);
    expect(messages.last['role'], 'assistant');
    expect(messages.last['content'], contains('已收到你的描述'));
    expect(events.map((event) => event.stage), containsAll([
      AiTraceStage.input,
      AiTraceStage.route,
      AiTraceStage.dispatch,
      AiTraceStage.argumentValidation,
      AiTraceStage.businessExecution,
      AiTraceStage.resultValidation,
      AiTraceStage.persistence,
      AiTraceStage.finalRender,
    ]));
    expect(
      events.where((event) => event.stage == AiTraceStage.businessExecution)
          .single.status,
      AiTraceStatus.succeeded,
    );
    final persistenceEvents = events
        .where((event) => event.stage == AiTraceStage.persistence)
        .toList(growable: false);
    expect(persistenceEvents, hasLength(2));
    expect(
      persistenceEvents.map((event) => event.status),
      everyElement(AiTraceStatus.succeeded),
    );
    final finalRenderEvents = events
        .where((event) => event.stage == AiTraceStage.finalRender)
        .toList(growable: false);
    expect(finalRenderEvents, hasLength(2));
    expect(
      finalRenderEvents.map((event) => event.status),
      everyElement(AiTraceStatus.succeeded),
    );
  });



  testWidgets('E4B 只补充有逐字证据的八字自然语言参数，再交给 App 校验执行',
      (tester) async {
    const traceId = 'abcdef0123456789abcdef0123456789';
    const query = '我在上海市出生，1990年1月2日早上八点半，男性，帮我排八字';
    final slotDraft = LocalAiBaziSlotDraft.fromModelText(
      '{"birth_date":{"value":null,"evidence":null},'
      '"birth_time":{"value":"08:30","evidence":"早上八点半"},'
      '"gender":{"value":null,"evidence":null},'
      '"birthplace":{"value":"上海市","evidence":"在上海市出生"}}',
      userText: query,
      requestedKeys: const {'birth_time', 'birthplace'},
      backend: 'cpu',
    );
    final service = _TextSendService(baziSlotDraft: slotDraft);
    final store = _MemoryConversationStore();
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 13, 12),
    );
    Map<String, String>? executedArguments;
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          traceRecorder: recorder,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) async {
            executedArguments = Map<String, String>.unmodifiable(arguments);
            return AssistantToolResult(
              toolId: 'bazi',
              title: '八字排盘',
              values: const {'完整排盘结果': '四柱：庚午、己丑、甲子、戊辰'},
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const ['local-engine:bazi'],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();
    expect(service.statusCalls, greaterThan(0));
    expect(
      AssistantConversationOrchestrator.shouldUseBaziSlotModel(
        query,
        const {'birth_time', 'birthplace'},
      ),
      isTrue,
    );

    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.baziSlotQueries, [query]);
    expect(service.baziSlotMissingKeys, [const {'birth_time', 'birthplace'}]);
    expect(service.baziSlotTraceIds, [traceId]);
    expect(executedArguments, const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'gender': 'male',
      'birthplace': '上海市',
    });
    expect(find.textContaining('四柱：庚午、己丑、甲子、戊辰'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(
      events.where((event) => event.route == 'bazi_slot_extraction').length,
      greaterThanOrEqualTo(2),
    );
    expect(
      events.any((event) =>
          event.stage == AiTraceStage.resultValidation &&
          event.route == 'bazi_slot_evidence_validation' &&
          event.status == AiTraceStatus.succeeded),
      isTrue,
    );
    expect(
      events.where((event) => event.route == 'bazi_slot_extraction')
          .where((event) => event.status == AiTraceStatus.succeeded)
          .every((event) => event.backend == 'cpu'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('八字助手在对话中分轮补齐参数并后台执行，不打开排盘页面',
      (tester) async {
    final service = _TextSendService();
    final store = _MemoryConversationStore();
    var pageOpened = false;
    const sourceIds = [
      'local-engine:bazi',
      'local-data:city-locations',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) => AssistantToolResult(
            toolId: 'bazi',
            title: '八字排盘',
            values: const {
              '完整排盘结果': '四柱：庚午、己丑、甲子、戊辰',
            },
            arguments: Map<String, String>.unmodifiable(arguments),
            sourceIds: sourceIds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String text) async {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我排八字');
    expect(find.textContaining('出生日期（公历'), findsWidgets);
    expect(find.text('打开八字排盘'), findsNothing);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, isEmpty);
    expect(
      service.baziSlotQueries,
      isEmpty,
      reason: '没有任何出生资料线索时，不调用 E4B 猜测参数',
    );

    await send('出生日期：1990年1月2日');
    expect(find.textContaining('出生日期（公历'), findsWidgets);
    expect(pageOpened, isFalse);

    final conversationsAfterDate = await store.getAssistantConversations();
    final messagesAfterDate = await store.getAssistantMessages(
      conversationId: conversationsAfterDate.single['id'] as int,
    );
    final latestClarification =
        messagesAfterDate.last['content'] as String;
    expect(
      latestClarification,
      contains('已识别的信息：出生日期（公历）：1990-01-02'),
    );
    expect(latestClarification, contains('目前还缺少：出生时间、性别、出生地点'));
    expect(
      latestClarification,
      isNot(contains('目前还缺少：出生日期（公历）')),
    );

    await send('出生时间：08:30；性别：男；出生地：上海市');
    expect(find.textContaining('四柱：庚午、己丑、甲子、戊辰'), findsOneWidget);
    expect(find.text('打开八字排盘'), findsNothing);
    expect(pageOpened, isFalse);
    expect(
      find.text('AI总结解读'),
      findsNothing,
      reason: '模型已就绪且排盘结果通过来源/参数契约后，应由助手自动解释',
    );
    expect(
      service.sentTexts.where((value) => value.contains('总结并解释刚才由 App 本地引擎返回的八字排盘结果')),
      hasLength(1),
    );

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    expect(messages.length, greaterThanOrEqualTo(7));
    final resultMessage = messages.firstWhere(
      (message) => (message['content'] as String).contains('完整排盘结果'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'bazi');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'gender': 'male',
      'birthplace': '上海市',
    });
    expect(metadata.sourceIds, sourceIds);
    expect(
      messages.where((message) =>
          message['role'] == 'user' &&
          (message['content'] as String).contains(
              '总结并解释刚才由 App 本地引擎返回的八字排盘结果')),
      isEmpty,
      reason: '自动解释指令是内部调度内容，不得伪装成用户发言持久化',
    );
    expect(
      messages.where((message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('已收到')),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('紫微助手在对话中分轮补齐参数并后台执行，不打开排盘页面',
      (tester) async {
    final service = _TextSendService();
    final store = _MemoryConversationStore();
    var pageOpened = false;
    const sourceIds = [
      'local-engine:ziwei',
      'local-data:city-locations',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const SizedBox.shrink();
          },
          testHeadlessToolExecutor: (arguments) => AssistantToolResult(
            toolId: 'ziwei',
            title: '紫微斗数排盘',
            values: const {
              '出生地坐标': '东经 121.4737，北纬 31.2304',
              '完整排盘结果': '出生资料：1990-01-02 08:30；十二宫星曜：命宫 ...',
            },
            arguments: Map<String, String>.unmodifiable(arguments),
            sourceIds: sourceIds,
            disclaimer: '传统术数文化参考。',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String text) async {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我排一个紫微斗数命盘');
    expect(find.textContaining('出生日期（公历'), findsWidgets);
    expect(find.text('打开紫微斗数排盘'), findsNothing);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, isEmpty);

    await send('出生日期：1990年1月2日');
    final conversationsAfterDate = await store.getAssistantConversations();
    final messagesAfterDate = await store.getAssistantMessages(
      conversationId: conversationsAfterDate.single['id'] as int,
    );
    final latestClarification =
        messagesAfterDate.last['content'] as String;
    expect(
      latestClarification,
      contains('已识别的信息：出生日期（公历）：1990-01-02'),
    );
    expect(
      latestClarification,
      contains('目前还缺少：出生时间、性别、出生地点'),
    );
    expect(pageOpened, isFalse);
    expect(service.sentTexts, isEmpty);

    await send('出生时间：08:30；性别：男；出生地：上海市');
    expect(find.textContaining('十二宫星曜：命宫'), findsOneWidget);
    expect(find.text('打开紫微斗数排盘'), findsNothing);
    expect(pageOpened, isFalse);
    expect(
      service.sentTexts,
      hasLength(1),
      reason: '确定性排盘结果通过来源和参数契约后，模型只负责自动解释',
    );
    expect(service.sentTexts.single, contains('总结并解释'));
    expect(service.sentTexts.single, contains('紫微斗数排盘'));
    expect(service.sentContexts.single, contains('当前角色：玄学大师'));

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultMessage = messages.firstWhere(
      (message) =>
          (message['content'] as String).contains('完整排盘结果'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(resultMessage['role'], 'assistant');
    expect(metadata.toolId, 'ziwei');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
      'gender': 'male',
      'birthplace': '上海市',
    });
    expect(metadata.sourceIds, sourceIds);
    expect(
      messages.where((message) =>
          message['role'] == 'user' &&
          (message['content'] as String).contains('总结并解释')),
      isEmpty,
      reason: '自动解释是内部调度指令，不得伪装成用户发言持久化',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('节气查询留在助手对话，返回校验结果后自动解释知识资产',
      (tester) async {
    final service = _TextSendService();
    final store = _MemoryConversationStore();
    var pageOpened = false;
    final executedArguments = <Map<String, String>>[];
    const sources = [
      'local-engine:solar-term-service',
      'local-asset:solar-term-knowledge',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开节气养生页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            final term = arguments['term'] ?? 'App 当前节气';
            return AssistantToolResult(
              toolId: 'solar_terms',
              title: '节气养生',
              values: {
                '目标节气': term,
                '通用养生常识': '现有节气知识资产中的原始内容',
                '倪师讲座相关整理': '【推断】现有资料中的整理内容',
                '节气三候': '一候原文；二候原文；三候原文',
                '起居调摄': '【推断】资料中的起居信息',
                '食疗资料': '现有资产中的食疗信息',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: sources,
              disclaimer: '只解释 App 已有节气资料，不生成个体诊断或用药建议。',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('查询立春养生');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.first, const {'term': '立春'});
    expect(find.textContaining('一候原文；二候原文；三候原文'), findsOneWidget);
    expect(find.textContaining('现有资产中的食疗信息'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('总结并解释实际输入'));
    expect(service.sentContexts.single, contains('当前角色：工具助手'));

    await send('查询当前节气');
    expect(executedArguments, hasLength(2));
    expect(executedArguments.last, isEmpty,
        reason: '没有指定节气时由 App 服务读取当前真实节气，不要求模型补算');
    expect(find.textContaining('App 当前节气'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(2));

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultMessages = messages.where(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('现有节气知识资产中的原始内容'),
    ).toList(growable: false);
    expect(resultMessages, hasLength(2));
    final specifiedMetadata = AssistantMessageMetadata.decode(
      resultMessages.first['metadata'] as String,
    );
    expect(specifiedMetadata.toolId, 'solar_terms');
    expect(specifiedMetadata.toolStatus, 'SUCCEEDED');
    expect(specifiedMetadata.toolArguments, const {'term': '立春'});
    expect(specifiedMetadata.sourceIds, sources);
    final currentMetadata = AssistantMessageMetadata.decode(
      resultMessages.last['metadata'] as String,
    );
    expect(currentMetadata.toolId, 'solar_terms');
    expect(currentMetadata.toolStatus, 'SUCCEEDED');
    expect(currentMetadata.toolArguments, isEmpty);
    expect(currentMetadata.sourceIds, sources);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Headless 结果契约失败时记录失败终态且不持久化', (tester) async {
    const traceId = 'abcdef0123456789abcdef0123456789';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 14),
    );
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          traceRecorder: recorder,
          testHeadlessToolExecutor: (arguments) => AssistantToolResult(
            toolId: 'wrong-tool-id',
            title: '无效测试结果',
            values: const {'结果': '不应进入会话'},
            arguments: arguments,
            sourceIds: const ['local-engine:test'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '帮我推算五运六气 2026-11-12',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Headless 工具结果未通过契约校验'), findsOneWidget);
    expect(find.textContaining('不应进入会话'), findsNothing);
    expect(service.sentTexts, isEmpty);
    final conversations = await _store.getAssistantConversations();
    expect(conversations, isEmpty);
    expect(
      events.where((event) => event.stage == AiTraceStage.resultValidation)
          .single.status,
      AiTraceStatus.failed,
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.resultValidation)
          .single.errorCode,
      'RESULT_CONTRACT_INVALID',
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.persistence)
          .single.status,
      AiTraceStatus.notStarted,
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.persistence)
          .single.errorCode,
      'RESULT_CONTRACT_INVALID',
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.finalRender)
          .single.status,
      AiTraceStatus.succeeded,
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.finalRender)
          .single.errorCode,
      'RESULT_CONTRACT_INVALID',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Native 发送失败后记录 finalRender 失败提示终态', (tester) async {
    const traceId = '50505050505050505050505050505050';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 20),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: _FailingTextSendService(),
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('native send failed in test'), findsOneWidget);
    final finalRender = events
        .where((event) =>
            event.traceId == traceId &&
            event.stage == AiTraceStage.finalRender)
        .single;
    expect(finalRender.status, AiTraceStatus.succeeded);
    expect(finalRender.errorCode, 'NATIVE_SEND_FAILED');
    expect(tester.takeException(), isNull);
  });

  testWidgets('症状整理空结果和用户确认路径都记录 finalRender 终态',
      (tester) async {
    const sendTraceId = '10101010101010101010101010101010';
    const emptyTraceId = '20202020202020202020202020202020';
    const confirmedTraceId = '30303030303030303030303030303030';
    final nextTraceIds = [sendTraceId, emptyTraceId, confirmedTraceId];
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => nextTraceIds.removeAt(0),
      clock: () => DateTime(2026, 11, 12, 20),
    );
    final service = _SequencedSymptomsTraceService([
      const LocalAiSymptomDraft(sourceTruncated: true),
      const LocalAiSymptomDraft(
        mainComplaint: '间断头痛',
        duration: '三天',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我间断头痛三天');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('整理本次症状'));
    await tester.pumpAndSettle();
    expect(
      find.text('原始输入记录曾被裁剪，但本次未提取到可核对内容。请补充遗漏描述后重新整理。'),
      findsOneWidget,
    );
    final emptyFinalRender = events
        .where((event) =>
            event.traceId == emptyTraceId &&
            event.stage == AiTraceStage.finalRender)
        .single;
    expect(emptyFinalRender.status, AiTraceStatus.succeeded);
    expect(emptyFinalRender.errorCode, 'EMPTY_SYMPTOM_DRAFT');

    await tester.tap(find.text('整理本次症状'));
    await tester.pumpAndSettle();
    expect(find.text('核对症状整理'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认这份整理'));
    await tester.pumpAndSettle();

    final confirmedFinalRender = events
        .where((event) =>
            event.traceId == confirmedTraceId &&
            event.stage == AiTraceStage.finalRender)
        .single;
    expect(confirmedFinalRender.status, AiTraceStatus.succeeded);
    expect(confirmedFinalRender.errorCode, isNull);
    expect(service.extractedTraceIds, [emptyTraceId, confirmedTraceId]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Page Tool 结果复用请求 TRACE ID 并记录执行、校验、持久化与恢复终态',
      (tester) async {
    const traceId = 'abcdefabcdefabcdefabcdefabcdefab';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 20),
    );
    final service = _PageToolTraceService();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _store,
          service: service,
          traceRecorder: recorder,
          testToolRouteBuilder: (tool, arguments) => Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('complete-page-tool'),
                  onPressed: () => Navigator.of(context).pop(
                    AssistantToolResult(
                      toolId: tool.id,
                      title: tool.title,
                      values: const {'结果': '页面结果已回传'},
                      arguments: arguments.values,
                      sourceIds: const ['local-engine:page-tool-test'],
                    ),
                  ),
                  child: const Text('完成页面工具'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我推算五运六气');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.text('打开五运六气推算'), findsOneWidget);

    await tester.tap(find.text('打开五运六气推算'));
    await tester.pumpAndSettle();
    expect(find.text('完成页面工具'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('complete-page-tool')));
    await tester.pumpAndSettle();

    expect(find.textContaining('页面结果已回传'), findsOneWidget);
    expect(service.restoredTranscripts, hasLength(1));
    final conversations = await _store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final messages = await _store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    expect(messages, hasLength(4));
    final pageResultMessage = messages.firstWhere(
      (message) =>
          (message['content'] as String).contains('页面结果已回传'),
    );
    final resultMetadata = AssistantMessageMetadata.decode(
      pageResultMessage['metadata'] as String,
    );
    expect(resultMetadata.toolId, 'yunqi');
    expect(resultMetadata.toolStatus, 'SUCCEEDED');
    expect(resultMetadata.sourceIds, const ['local-engine:page-tool-test']);
    expect(resultMetadata.traceId, traceId);
    expect(messages.last['role'], 'assistant');
    expect(messages.last['content'], contains('已收到你的描述'));

    final toolExecutionEvents = events
        .where((event) => event.stage == AiTraceStage.toolExecution)
        .toList(growable: false);
    expect(toolExecutionEvents.map((event) => event.status), containsAll([
      AiTraceStatus.notStarted,
      AiTraceStatus.succeeded,
    ]));
    expect(
      events.where((event) => event.stage == AiTraceStage.businessExecution)
          .single.status,
      AiTraceStatus.succeeded,
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.resultValidation)
          .map((event) => event.status),
      containsAll([AiTraceStatus.succeeded, AiTraceStatus.succeeded]),
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.persistence)
          .last.status,
      AiTraceStatus.succeeded,
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.persistedState)
          .single.status,
      AiTraceStatus.succeeded,
    );
    expect(
      events.where((event) => event.stage == AiTraceStage.finalRender)
          .last.status,
      AiTraceStatus.succeeded,
    );
    expect(events.every((event) => event.traceId == traceId), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Page Tool 结果持久化状态未知时显示告警且不自动重跑工具',
      (tester) async {
    const traceId = 'fedcba9876543210fedcba9876543210';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 13, 18),
    );
    final store = _MemoryConversationStore();
    final service = _PageToolTraceService();
    var pageResultReturned = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          traceRecorder: recorder,
          testToolRouteBuilder: (tool, arguments) => Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('complete-page-tool-persistence-failure'),
                  onPressed: () {
                    pageResultReturned += 1;
                    Navigator.of(context).pop(
                      AssistantToolResult(
                        toolId: tool.id,
                        title: tool.title,
                        values: const {'结果': '页面结果已回传'},
                        arguments: arguments.values,
                        sourceIds: const ['local-engine:page-tool-test'],
                      ),
                    );
                  },
                  child: const Text('完成页面工具'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我推算五运六气');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开五运六气推算'));
    await tester.pumpAndSettle();
    expect(find.text('完成页面工具'), findsOneWidget);

    // Fail only the tool-result row; the initial request has already been saved.
    store.failNextSingleMessageSave = true;
    await tester.tap(
      find.byKey(const ValueKey('complete-page-tool-persistence-failure')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('页面结果已回传'), findsOneWidget);
    expect(
      find.textContaining('历史保存状态未知'),
      findsOneWidget,
    );
    expect(find.textContaining('未自动重跑'), findsOneWidget);
    expect(pageResultReturned, 1);

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final persisted = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    expect(
      persisted.any((message) =>
          (message['content'] as String).contains('页面结果已回传')),
      isFalse,
      reason: '故障注入必须真实命中工具结果写入失败，不能假装历史已保存',
    );

    final persistenceFailure = events.singleWhere(
      (event) =>
          event.stage == AiTraceStage.persistence &&
          event.errorCode == 'TOOL_RESULT_PERSISTENCE_UNKNOWN',
    );
    expect(persistenceFailure.status, AiTraceStatus.unknown);
    final persistedStateFailure = events.singleWhere(
      (event) =>
          event.stage == AiTraceStage.persistedState &&
          event.errorCode == 'TOOL_RESULT_PERSISTENCE_UNKNOWN',
    );
    expect(persistedStateFailure.status, AiTraceStatus.unknown);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TRACE 开启时同一轮 ID 贯穿 Native 调用与 user/assistant metadata',
      (tester) async {
    const traceId = '0123456789abcdef0123456789abcdef';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async {
        events.add(event);
      },
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 12),
    );
    final service = _TextSendService();

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _store,
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTraceIds, [traceId]);
    final conversations = await _store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final conversationId = conversations.single['id'] as int;
    final messages = await _store.getAssistantMessages(
      conversationId: conversationId,
    );
    expect(messages, hasLength(2));
    final userMetadata = AssistantMessageMetadata.decode(
      messages[0]['metadata'] as String,
    );
    final assistantMetadata = AssistantMessageMetadata.decode(
      messages[1]['metadata'] as String,
    );
    expect(userMetadata.traceId, traceId);
    expect(assistantMetadata.traceId, traceId);
    expect(events.map((event) => event.stage), containsAll([
      AiTraceStage.input,
      AiTraceStage.retrieval,
      AiTraceStage.contextAssembly,
      AiTraceStage.modelInput,
      AiTraceStage.nativeInference,
      AiTraceStage.modelOutput,
      AiTraceStage.persistence,
      AiTraceStage.finalRender,
    ]));
    expect(events.where((event) => event.stage == AiTraceStage.retrieval)
        .every((event) => event.sourceIds.isEmpty), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E4B 意图判别失败时退回确定性澄清，不执行任一工具', (tester) async {
    final service = _FailingIntentSelectionService();
    const traceId = 'fedcba9876543210fedcba9876543210';
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (_) async {},
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 13, 14),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _store,
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄学大师').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '推算五运六气，并查询黄历',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.intentQueries, ['推算五运六气，并查询黄历']);
    expect(service.intentCandidateIds, [
      ['yunqi', 'almanac'],
    ]);
    expect(find.textContaining('多个工具'), findsOneWidget);
    expect(find.text('打开八字排盘'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('含个人症状的歧义请求不把健康文本送入工具意图模型', (tester) async {
    final service = _TextSendService(
      intentResolution: const LocalAiIntentResolution(
        action: LocalAiIntentAction.select,
        toolId: 'bazi',
        backend: 'cpu',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '我最近三天口苦，帮我排个盘',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.intentQueries, isEmpty);
    expect(find.textContaining('你想使用哪一种排盘工具'), findsOneWidget);
    expect(find.text('打开八字排盘'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E4B 只从 Headless 候选中选择，并在当前对话回传真实工具结果', (tester) async {
    const traceId = '0123456789abcdef0123456789abcdef';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 13, 13),
    );
    final service = _TextSendService(
      intentResolution: const LocalAiIntentResolution(
        action: LocalAiIntentAction.select,
        toolId: 'almanac',
        backend: 'cpu',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _store,
          traceRecorder: recorder,
          testHeadlessToolExecutor: (arguments) async => AssistantToolResult(
            toolId: 'almanac',
            title: '每日黄历',
            values: const {'宜': '测试事项'},
            arguments: Map<String, String>.unmodifiable(arguments),
            sourceIds: const ['test:almanac'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄学大师').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '推算五运六气，并查询黄历',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.intentQueries, ['推算五运六气，并查询黄历']);
    expect(service.intentCandidateIds, [
      ['yunqi', 'almanac'],
    ]);
    expect(service.intentTraceIds, [traceId]);
    expect(find.textContaining('每日黄历'), findsWidgets);
    expect(find.textContaining('宜：测试事项'), findsOneWidget);
    expect(find.text('打开每日黄历'), findsNothing);
    expect(events.map((event) => event.stage), containsAll([
      AiTraceStage.nativeInference,
      AiTraceStage.modelOutput,
      AiTraceStage.resultValidation,
      AiTraceStage.route,
      AiTraceStage.dispatch,
    ]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('玄学模式普通文本也使用同一轮 TRACE ID 和上下文阶段', (tester) async {
    const traceId = 'abcdef0123456789abcdef0123456789';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 13),
    );
    final service = _TextSendService();

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _store,
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄学大师').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '介绍传统术数文化的历史背景');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTraceIds, [traceId]);
    expect(events.map((event) => event.stage), containsAll([
      AiTraceStage.input,
      AiTraceStage.contextAssembly,
      AiTraceStage.modelInput,
      AiTraceStage.nativeInference,
      AiTraceStage.modelOutput,
      AiTraceStage.persistence,
      AiTraceStage.finalRender,
    ]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('玄学模式普通文本调用也必须透传本轮 TRACE ID', (tester) async {
    const traceId = 'abcdef0123456789abcdef0123456789';
    final events = <AiTraceEvent>[];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceId,
      clock: () => DateTime(2026, 11, 12, 12),
    );
    final service = _TextSendService();

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          conversationStore: _store,
          traceRecorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄学大师').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '介绍紫微斗数的文化背景');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTraceIds, [traceId]);
    expect(service.sentContexts.single, contains('玄学大师'));
    expect(events.map((event) => event.stage), containsAll([
      AiTraceStage.input,
      AiTraceStage.nativeInference,
      AiTraceStage.modelOutput,
      AiTraceStage.persistence,
      AiTraceStage.finalRender,
    ]));
    expect(tester.takeException(), isNull);
  });


  testWidgets('梅花数字起卦在助手对话内执行并自动解释真实结果', (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final events = <AiTraceEvent>[];
    var pageOpened = false;
    Map<String, String>? executedArguments;
    var executionCount = 0;
    var traceSequence = 0;
    final traceIds = [
      '11111111111111111111111111111111',
      '22222222222222222222222222222222',
    ];
    final recorder = AiTraceRecorder(
      enabled: true,
      writer: (event) async => events.add(event),
      idFactory: () => traceIds[traceSequence++],
      clock: () => DateTime(2026, 11, 13, 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          traceRecorder: recorder,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开梅花页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executionCount += 1;
            executedArguments = Map<String, String>.unmodifiable(arguments);
            return AssistantToolResult(
              toolId: 'meihua',
              title: '梅花易数数字起卦',
              values: const {
                '第一数（上卦）': '3',
                '第二数（下卦）': '7',
                '主卦': '第17卦 泽雷随',
                '互卦': '第53卦 风山渐',
                '变卦': '第25卦 天雷无妄',
                '推算过程': '数字起卦结果由 App 原有算法返回',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const [
                'local-engine:meihua',
                'local-data:yijing-hexagrams',
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      '梅花易数起卦，用 3 和 7，公历日期 2026-11-13',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(executionCount, 1);
    expect(executedArguments, const {
      'method': 'number',
      'first': '3',
      'second': '7',
      'date': '2026-11-13',
    });
    expect(find.textContaining('第17卦 泽雷随'), findsOneWidget);
    expect(find.textContaining('第53卦 风山渐'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(1));
    expect(
      service.sentTexts.single,
      contains('总结并解释实际输入'),
    );

    final conversations = await store.getAssistantConversations();
    expect(conversations, hasLength(1));
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultMessage = messages.firstWhere(
      (message) =>
          (message['content'] as String).contains('第17卦 泽雷随'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'meihua');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'method': 'number',
      'first': '3',
      'second': '7',
      'date': '2026-11-13',
    });
    expect(metadata.sourceIds, const [
      'local-engine:meihua',
      'local-data:yijing-hexagrams',
    ]);
    expect(events.map((event) => event.stage), containsAll([
      AiTraceStage.argumentValidation,
      AiTraceStage.businessExecution,
      AiTraceStage.resultValidation,
      AiTraceStage.persistence,
      AiTraceStage.finalRender,
    ]));
    expect(
      events.any((event) =>
          event.stage == AiTraceStage.businessExecution &&
          event.toolId == 'meihua' &&
          event.status == AiTraceStatus.succeeded),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('小六壬助手只追问缺失参数并在对话中执行真实规则结果',
      (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开小六壬页面'));
          },
          testHeadlessToolExecutor: (arguments) async {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return XiaoliurenToolExecutor.execute(arguments);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我用小六壬起课');
    expect(
      find.textContaining('目前还缺少：公历日期、时辰、起课口径'),
      findsOneWidget,
    );
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty);
    expect(pageOpened, isFalse);

    await send('公历日期：2026-11-14');
    expect(
      find.textContaining('已识别的信息：公历日期：2026-11-14'),
      findsOneWidget,
    );
    expect(find.textContaining('目前还缺少：时辰、起课口径'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty);

    final conversationsBeforeExecute = await store.getAssistantConversations();
    final pendingMessages = await store.getAssistantMessages(
      conversationId: conversationsBeforeExecute.single['id'] as int,
    );
    final pendingMetadata = AssistantMessageMetadata.decode(
      pendingMessages.last['metadata'] as String,
    );
    expect(pendingMetadata.toolId, 'xiaoliuren');
    expect(pendingMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(pendingMetadata.toolArguments, const {'date': '2026-11-14'});

    await send('午时，通行掌诀');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'date': '2026-11-14',
      'hour': '午时',
      'rule': 'common',
    });
    expect(find.textContaining('【小六壬起课执行结果】'), findsOneWidget);
    expect(find.text('打开小六壬起课'), findsNothing);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('小六壬起课'));
    expect(service.sentContexts.single, contains('当前角色：玄学大师'));

    final conversations = await store.getAssistantConversations();
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultMessage = messages.firstWhere(
      (message) =>
          (message['content'] as String).contains('【小六壬起课执行结果】'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(resultMessage['role'], 'assistant');
    expect(metadata.toolId, 'xiaoliuren');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'date': '2026-11-14',
      'hour': '午时',
      'rule': 'common',
    });
    expect(metadata.sourceIds, const [
      'local-engine:xiaoliuren',
      'local-data:xiaoliuren-rule-data',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('易经数字起卦在对话中分轮追问、执行并持久化来源', (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开易经页面'));
          },
          testHeadlessToolExecutor: (arguments) async {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return YiJingToolExecutor.execute(arguments);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我用易经数字起卦');
    expect(find.textContaining('目前还缺少：第一数、第二数'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty);
    expect(pageOpened, isFalse);

    await send('第一数：3');
    expect(find.textContaining('目前还缺少：第二数'), findsOneWidget);
    expect(executedArguments, isEmpty);

    final conversationsBeforeExecution = await store.getAssistantConversations();
    final pendingRows = await store.getAssistantMessages(
      conversationId: conversationsBeforeExecution.single['id'] as int,
    );
    final pendingMetadata = AssistantMessageMetadata.decode(
      pendingRows.last['metadata'] as String,
    );
    expect(pendingMetadata.toolId, 'yijing');
    expect(pendingMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(pendingMetadata.toolArguments, const {
      'method': 'number',
      'first': '3',
    });

    await send('第二数：7');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'method': 'number',
      'first': '3',
      'second': '7',
    });
    expect(find.textContaining('【易经起卦执行结果】'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('易经起卦'));

    final conversations = await store.getAssistantConversations();
    final rows = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultRow = rows.firstWhere(
      (row) => (row['content'] as String).contains('【易经起卦执行结果】'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultRow['metadata'] as String,
    );
    expect(metadata.toolId, 'yijing');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'method': 'number',
      'first': '3',
      'second': '7',
    });
    expect(metadata.sourceIds, const [
      'local-engine:yijing',
      'local-data:yijing-hexagrams',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('易经手动选卦支持分轮补充上下卦和静卦参数', (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testHeadlessToolExecutor: (arguments) async {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return YiJingToolExecutor.execute(arguments);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我用易经手动选卦');
    expect(find.textContaining('目前还缺少：上卦、下卦、动爻'), findsOneWidget);
    expect(executedArguments, isEmpty);

    await send('上卦乾');
    expect(find.textContaining('目前还缺少：下卦、动爻'), findsOneWidget);
    await send('下卦坤，静卦');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'method': 'manual',
      'upper': '1',
      'lower': '8',
      'moving': '0',
    });
    expect(find.textContaining('【易经起卦执行结果】'), findsOneWidget);
    expect(service.sentTexts, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('易经当前时间和铜钱模式只使用 App 注入并保存实际执行值',
      (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testHeadlessToolExecutor: (arguments) async {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return YiJingToolExecutor.execute(arguments);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我按当前时间用易经起卦');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.first['method'], 'time');
    final actualAt = DateTime.tryParse(executedArguments.first['at'] ?? '');
    expect(actualAt, isNotNull);
    expect(actualAt!.toIso8601String(), executedArguments.first['at']);

    await send('帮我用易经铜钱摇卦');
    expect(executedArguments, hasLength(2));
    expect(executedArguments.last['method'], 'coins');
    final coinValues = executedArguments.last['coins']!
        .split(',')
        .map(int.parse)
        .toList(growable: false);
    expect(coinValues, hasLength(6));
    expect(coinValues.every(const {6, 7, 8, 9}.contains), isTrue);
    expect(service.sentTexts, hasLength(2));

    final conversations = await store.getAssistantConversations();
    final rows = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final persistedToolRows = rows.where((row) {
      final metadata = AssistantMessageMetadata.decode(row['metadata'] as String? ?? '');
      return metadata.toolId == 'yijing' &&
          metadata.toolStatus == 'SUCCEEDED' &&
          (row['content'] as String).startsWith('【易经起卦执行结果】');
    }).toList(growable: false);
    expect(persistedToolRows, hasLength(2));
    final timeMetadata = AssistantMessageMetadata.decode(
      persistedToolRows.first['metadata'] as String,
    );
    final coinsMetadata = AssistantMessageMetadata.decode(
      persistedToolRows.last['metadata'] as String,
    );
    expect(timeMetadata.toolArguments['at'], executedArguments.first['at']);
    expect(coinsMetadata.toolArguments['coins'], executedArguments.last['coins']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('梅花数字起卦在对话中分轮追问并恢复已提供参数，不打开页面',
      (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开梅花页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return AssistantToolResult(
              toolId: 'meihua',
              title: '梅花易数数字起卦',
              values: const {
                '第一数（上卦）': '3',
                '第二数（下卦）': '7',
                '主卦': '第17卦 泽雷随',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const [
                'local-engine:meihua',
                'local-data:yijing-hexagrams',
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('梅花易数数字起卦');
    expect(find.textContaining('目前还缺少：第一数（上卦）、第二数（下卦）'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(pageOpened, isFalse);

    await send('第一数：3');
    expect(find.textContaining('目前还缺少：第二数（下卦）'), findsOneWidget);
    expect(find.textContaining('第一数（上卦）：3'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(pageOpened, isFalse);

    await send('7');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single['method'], 'number');
    expect(executedArguments.single['first'], '3');
    expect(executedArguments.single['second'], '7');
    expect(executedArguments.single['date'], isNotEmpty);
    expect(find.textContaining('第17卦 泽雷随'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('梅花起卦方式在对话中追问、执行并返回校验结果，不打开页面',
      (tester) async {
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: _MemoryConversationStore(),
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开梅花页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            final methodLabel = switch (arguments['method']) {
              'number' => '数字起卦',
              'time' => '时间起卦',
              'random' => '随机起卦',
              _ => '未知方式',
            };
            return AssistantToolResult(
              toolId: 'meihua',
              title: '梅花易数起卦',
              values: {
                '起卦方式': methodLabel,
                '公历日期': arguments['date'] ?? 'MISSING',
                '主卦': '第17卦 泽雷随',
                '推算过程': 'App 原有算法返回的实际执行结果',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const [
                'local-engine:meihua',
                'local-data:yijing-hexagrams',
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    // Ambiguous method stays in the conversation and asks one targeted question.
    await send('梅花易数起卦，申时');
    expect(find.textContaining('请先选择：数字起卦、时间起卦或随机起卦'), findsOneWidget);
    expect(executedArguments, isEmpty);

    // The follow-up method and inputs are merged with the pending conversation.
    await send('时间起卦，公历日期 2026-11-13');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'method': 'time',
      'date': '2026-11-13',
      'hour_branch': '申',
    });
    expect(find.textContaining('时间起卦'), findsWidgets);

    await send('梅花易数随机起卦，公历日期 2026-11-13');
    expect(executedArguments, hasLength(2));
    expect(executedArguments.last, const {
      'method': 'random',
      'date': '2026-11-13',
    });

    await send('梅花易数数字起卦，用 3 和 7，公历日期 2026-11-13');
    expect(executedArguments, hasLength(3));
    expect(executedArguments.last, const {
      'method': 'number',
      'first': '3',
      'second': '7',
      'date': '2026-11-13',
    });
    expect(pageOpened, isFalse);
    expect(find.textContaining('第17卦 泽雷随'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('称骨助手在当前对话分轮收集出生资料、后台执行并解释，不打开页面',
      (tester) async {
    final service = _TextSendService();
    final store = _MemoryConversationStore();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开称骨页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return AssistantToolResult(
              toolId: 'chenggu',
              title: '袁天罡称骨',
              values: const {
                '出生公历': '1990-01-02 08:30',
                '总骨重': '4两2钱（42钱）',
                '称骨歌诀': '传统歌诀示例文本',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const [
                'local-engine:chenggu',
                'local-data:chenggu-bone-weight',
              ],
              disclaimer: '仅供传统民俗文化学习参考。',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我称骨');
    expect(find.textContaining('出生日期（公历）'), findsOneWidget);
    expect(find.textContaining('出生时间（当地钟表时间）'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty,
        reason: '缺少简单参数时直接由确定性代码追问，不调用 E4B');
    expect(pageOpened, isFalse);

    await send('出生日期：1990年1月2日');
    expect(executedArguments, isEmpty);
    expect(find.textContaining('出生时间（当地钟表时间）').last, findsOneWidget);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, isEmpty);

    await send('出生时间：08:30');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
    });
    expect(find.textContaining('4两2钱（42钱）'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(
      service.sentTexts.any((value) => value.contains('袁天罡称骨')),
      isTrue,
      reason: '只有真实执行结果通过来源和参数校验后才进入 AI 解释',
    );

    final conversations = await store.getAssistantConversations();
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultMessage = messages.firstWhere(
      (message) => (message['content'] as String).contains('4两2钱'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'chenggu');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'birth_date': '1990-01-02',
      'birth_time': '08:30',
    });
    expect(metadata.sourceIds, contains('local-engine:chenggu'));
    expect(metadata.sourceIds, contains('local-data:chenggu-bone-weight'));
    expect(tester.takeException(), isNull);
  });


  testWidgets('黄帝四季歌在当前助手对话分轮追问、执行本地结果并解释，不打开页面',
      (tester) async {
    final service = _TextSendService();
    final store = _MemoryConversationStore();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开黄帝四季歌页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return AssistantToolResult(
              toolId: 'huangdi_siji',
              title: '轩辕黄帝四季歌',
              values: const {
                '农历月份': '十二月',
                '季节口径': '冬',
                '出生时辰': '戌时',
                '对应部位': '腰',
                '命格标题': '冬月戌时',
                '部位诗': '本地四季歌表返回的诗句',
                '现有释义': 'App 本地数据返回的原有释义',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const [
                'local-engine:huangdi-siji',
                'local-data:huangdi-siji-ge',
              ],
              disclaimer: '传统民俗文化资料，仅供文化学习参考。',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('查询黄帝四季歌');
    expect(find.textContaining('出生日期（公历）'), findsOneWidget);
    expect(find.textContaining('出生时间（当地钟表时间）'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty,
        reason: '缺少简单参数时由确定性代码追问，不调用 E4B');
    expect(pageOpened, isFalse);

    await send('出生日期：1990年1月2日');
    expect(executedArguments, isEmpty);
    expect(find.textContaining('目前还缺少：出生时间（当地钟表时间）'), findsOneWidget);
    expect(service.sentTexts, isEmpty);
    expect(pageOpened, isFalse);

    await send('不要取消，出生时间：晚上8:30');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'birth_date': '1990-01-02',
      'birth_time': '20:30',
    });
    expect(find.textContaining('本地四季歌表返回的诗句'), findsOneWidget);
    expect(find.textContaining('冬月戌时'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(
      service.sentTexts.any((value) => value.contains('轩辕黄帝四季歌')),
      isTrue,
      reason: '只有 Headless 真实结果通过来源/参数校验后才触发 AI 解释',
    );

    final conversations = await store.getAssistantConversations();
    final messages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultMessage = messages.firstWhere(
      (message) => (message['content'] as String).contains('本地四季歌表返回的诗句'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultMessage['metadata'] as String,
    );
    expect(metadata.toolId, 'huangdi_siji');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'birth_date': '1990-01-02',
      'birth_time': '20:30',
    });
    expect(metadata.sourceIds, contains('local-engine:huangdi-siji'));
    expect(metadata.sourceIds, contains('local-data:huangdi-siji-ge'));
    expect(tester.takeException(), isNull);
  });


  testWidgets('经方单位换算在助手对话内追问制式、执行并交由 AI 解释', (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开经方换算页面'));
          },
          testHeadlessToolExecutor: (arguments) async {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return DosageToolExecutor.execute(arguments);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('把1.5两换算成克');
    expect(find.textContaining('目前还缺少：度量标准'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty,
        reason: '确定性参数缺失只做澄清，不调用 E4B');
    expect(pageOpened, isFalse);

    final pendingConversations = await store.getAssistantConversations();
    final pendingRows = await store.getAssistantMessages(
      conversationId: pendingConversations.single['id'] as int,
    );
    final pendingMetadata = AssistantMessageMetadata.decode(
      pendingRows.last['metadata'] as String,
    );
    expect(pendingMetadata.toolId, 'dosage');
    expect(pendingMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(pendingMetadata.toolArguments, const {
      'value': '1.5',
      'unit': '两',
    });

    await send('汉制');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'value': '1.5',
      'unit': '两',
      'standard': 'han',
    });
    expect(find.textContaining('23.438'), findsOneWidget);
    expect(find.textContaining('仅单位换算；不计算药物处方剂量'), findsOneWidget);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(1),
        reason: '只有 App 计算并通过 sourceIds/arguments 校验后才交给模型解释');

    final conversations = await store.getAssistantConversations();
    final rows = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultRow = rows.firstWhere(
      (row) => (row['content'] as String)
          .startsWith('【经方度量衡单位换算执行结果】'),
    );
    final metadata = AssistantMessageMetadata.decode(
      resultRow['metadata'] as String,
    );
    expect(metadata.toolId, 'dosage');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'value': '1.5',
      'unit': '两',
      'standard': 'han',
    });
    expect(metadata.sourceIds, const [
      DosageToolExecutor.sourceId,
      DosageToolExecutor.factorsSourceId,
    ]);
    expect(tester.takeException(), isNull);
  });


  testWidgets('子午流注在助手对话中追问时刻、执行四法并解释真实结果',
      (tester) async {
    final store = _MemoryConversationStore();
    final service = _TextSendService();
    final executedArguments = <Map<String, String>>[];
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开子午流注页面'));
          },
          testHeadlessToolExecutor: (arguments) async {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            return ZiWuLiuZhuToolExecutor.execute(arguments);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我计算2026-11-14子午流注开穴');
    expect(find.textContaining('目前还缺少：具体时刻（HH:mm）'), findsOneWidget);
    expect(executedArguments, isEmpty);
    expect(service.sentTexts, isEmpty,
        reason: '缺少计算时刻时只在对话澄清，不调用 E4B 或业务引擎');
    expect(pageOpened, isFalse);

    final pendingConversations = await store.getAssistantConversations();
    final pendingRows = await store.getAssistantMessages(
      conversationId: pendingConversations.single['id'] as int,
    );
    final pendingMetadata = AssistantMessageMetadata.decode(
      pendingRows.last['metadata'] as String,
    );
    expect(pendingMetadata.toolId, 'ziwu_liuzhu');
    expect(pendingMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(pendingMetadata.toolArguments, const {'date': '2026-11-14'});

    await send('10:30');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single, const {
      'date': '2026-11-14',
      'time': '10:30',
      'at': '2026-11-14T10:30',
    });
    expect(find.textContaining('灵龟八法'), findsWidgets);
    expect(find.textContaining('纳甲法'), findsWidgets);
    expect(find.textContaining('飞腾八法'), findsWidgets);
    expect(pageOpened, isFalse);
    expect(service.sentTexts, hasLength(1),
        reason: '只有 App 执行并通过 sourceIds/arguments 校验后才进入 AI 解释');

    final conversations = await store.getAssistantConversations();
    final rows = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final resultRow = rows.firstWhere((row) {
      final metadata = AssistantMessageMetadata.decode(
        row['metadata'] as String? ?? '',
      );
      return metadata.toolId == 'ziwu_liuzhu' &&
          metadata.toolStatus == 'SUCCEEDED' &&
          metadata.sourceIds.contains(ZiWuLiuZhuToolExecutor.sourceId);
    });
    final metadata = AssistantMessageMetadata.decode(
      resultRow['metadata'] as String,
    );
    expect(metadata.toolId, 'ziwu_liuzhu');
    expect(metadata.toolStatus, 'SUCCEEDED');
    expect(metadata.toolArguments, const {
      'date': '2026-11-14',
      'time': '10:30',
      'at': '2026-11-14T10:30',
    });
    expect(metadata.sourceIds, const [
      ZiWuLiuZhuToolExecutor.sourceId,
      ZiWuLiuZhuToolExecutor.referenceSourceId,
    ]);
    expect(tester.takeException(), isNull);
  });



  testWidgets('周公解梦在对话中追问缺参、处理候选并接收补充情节', (tester) async {
    final service = _TextSendService();
    final store = _MemoryConversationStore();
    final executedArguments = <Map<String, String>>[];
    var executionCount = 0;
    var pageOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          conversationStore: store,
          service: service,
          testToolRouteBuilder: (_, __) {
            pageOpened = true;
            return const Scaffold(body: Text('不应打开解梦页面'));
          },
          testHeadlessToolExecutor: (arguments) {
            executedArguments.add(Map<String, String>.unmodifiable(arguments));
            executionCount += 1;
            final ambiguous = executionCount == 1;
            return AssistantToolResult(
              toolId: 'dream',
              title: '周公解梦',
              values: {
                '检索状态': ambiguous
                    ? 'CANDIDATES_REQUIRE_CLARIFICATION'
                    : 'SINGLE_MATCH',
                if (ambiguous)
                  '候选列表': '蛇；蛇咬；蛇缠身；很多蛇',
                if (!ambiguous)
                  '梦境词条': '梦见蛇咬',
                if (!ambiguous)
                  '词条释义原文': '本地数据集中的原文释义',
              },
              arguments: Map<String, String>.unmodifiable(arguments),
              sourceIds: const ['local-data:dream-dataset-412'],
              disclaimer: '传统民俗文本，不是现实预测。',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> send(String value) async {
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
    }

    await send('帮我解梦');
    expect(executedArguments, isEmpty,
        reason: '缺少梦境内容时只追问，不调用本地检索或模型');
    expect(find.textContaining('还不足以检索'), findsOneWidget);
    expect(service.sentTexts, isEmpty);

    await send('昨晚梦见蛇');
    expect(executedArguments, hasLength(1));
    expect(executedArguments.single['dream_text'], '昨晚梦见蛇');
    expect(service.sentTexts, hasLength(1));
    expect(service.sentTexts.single, contains('不得替用户挑选或排序'));
    expect(pageOpened, isFalse);

    final conversations = await store.getAssistantConversations();
    final firstResultMessages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final candidateMessage = firstResultMessages.firstWhere(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('CANDIDATES_REQUIRE_CLARIFICATION'),
    );
    final candidateMetadata = AssistantMessageMetadata.decode(
      candidateMessage['metadata'] as String,
    );
    expect(candidateMetadata.toolId, 'dream');
    expect(candidateMetadata.toolStatus, 'AWAITING_PARAMETERS');
    expect(candidateMetadata.sourceIds, const ['local-data:dream-dataset-412']);

    await send('是被蛇咬了');
    expect(executedArguments, hasLength(2));
    expect(executedArguments.last['dream_text'], contains('是被蛇咬了'));
    expect(service.sentTexts, hasLength(2));
    expect(service.sentTexts.last, contains('App 本地梦境民俗数据集'));
    expect(service.sentTexts.last, contains('SINGLE_MATCH'));
    expect(pageOpened, isFalse);

    final finalMessages = await store.getAssistantMessages(
      conversationId: conversations.single['id'] as int,
    );
    final finalResult = finalMessages.lastWhere(
      (message) =>
          message['role'] == 'assistant' &&
          (message['content'] as String).contains('SINGLE_MATCH'),
    );
    final finalMetadata = AssistantMessageMetadata.decode(
      finalResult['metadata'] as String,
    );
    expect(finalMetadata.toolId, 'dream');
    expect(finalMetadata.toolStatus, 'SUCCEEDED');
    expect(
      finalMetadata.toolArguments['dream_text'],
      contains('是被蛇咬了'),
    );
    expect(tester.takeException(), isNull);
  });

  mainRedFlagEntrypointOrderingTests();
}


class _WidgetRedFlagDetector implements RedFlagDetector {
  const _WidgetRedFlagDetector({
    required this.events,
    required this.matchedRuleIds,
    required this.subject,
  });

  final List<String> events;
  final List<String> matchedRuleIds;
  final RedFlagSubject subject;

  @override
  Future<RedFlagAssessment?> assess(RedFlagInput input) async {
    events.add('gate:${input.source.name}');
    return RedFlagAssessment(
      inputSource: input.source,
      detectorId: 'test-only-detector',
      detectorVersion: 'test-only-1',
      ruleSetVersion: 'test-reviewed-rule-set-1',
      subject: subject,
      time: RedFlagTime.current,
      polarity: RedFlagPolarity.affirmed,
      ruleSetReviewed: true,
      detectorCoverageComplete: true,
      matchedRuleIds: matchedRuleIds,
    );
  }
}

class _OrderedIntentSendService extends _TextSendService {
  _OrderedIntentSendService(this.events);

  final List<String> events;

  @override
  Future<LocalAiIntentResolution> resolveAssistantIntentWithTrace({
    required String query,
    required List<LocalAiIntentCandidate> candidates,
    required String traceId,
  }) {
    events.add('intent');
    return super.resolveAssistantIntentWithTrace(
      query: query,
      candidates: candidates,
      traceId: traceId,
    );
  }
}

void mainRedFlagEntrypointOrderingTests() {
  group('红旗门禁注入入口顺序', () {
    testWidgets('阻断结果必须早于意图识别和模型调用', (tester) async {
      final events = <String>[];
      final service = _OrderedIntentSendService(events);
      final gate = RedFlagGate(
        detector: _WidgetRedFlagDetector(
          events: events,
          matchedRuleIds: const ['reviewed-test-rule'],
          subject: RedFlagSubject.self,
        ),
        timeout: const Duration(milliseconds: 100),
      );
      final recorder = AiTraceRecorder(
        enabled: true,
        writer: (_) async {},
        idFactory: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(
            conversationStore: _store,
            service: service,
            imagePicker: _EmptyLocalAiImagePicker(),
            redFlagGate: gate,
            traceRecorder: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The model-ready state is asynchronous. Do not mistake a disabled send
      // button for a successful preflight-order test.
      for (var attempt = 0;
          attempt < 50 && find.byTooltip('释放模型内存').evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byTooltip('释放模型内存'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '我现在身体不舒服');
      await tester.pump();
      final sendButton = find.ancestor(
        of: find.byTooltip('发送'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(events, ['gate:currentText']);
      expect(service.intentQueries, isEmpty);
      expect(service.sentTexts, isEmpty);
      expect(find.textContaining('安全评估命中阻断条件'), findsOneWidget);
    });

    testWidgets('只有 CLEAR 才允许继续进入确定性意图候选筛选', (tester) async {
      final events = <String>[];
      final service = _OrderedIntentSendService(events);
      final gate = RedFlagGate(
        detector: _WidgetRedFlagDetector(
          events: events,
          matchedRuleIds: const [],
          subject: RedFlagSubject.knowledge,
        ),
        timeout: const Duration(milliseconds: 100),
      );
      final recorder = AiTraceRecorder(
        enabled: true,
        writer: (_) async {},
        idFactory: () => 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(
            conversationStore: _store,
            service: service,
            imagePicker: _EmptyLocalAiImagePicker(),
            redFlagGate: gate,
            traceRecorder: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0;
          attempt < 50 && find.byTooltip('释放模型内存').evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byTooltip('释放模型内存'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '我想排盘');
      await tester.pump();
      final sendButton = find.ancestor(
        of: find.byTooltip('发送'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(events, ['gate:currentText', 'intent']);
      expect(service.intentQueries, ['我想排盘']);
    });

    testWidgets('未配置 Gate 时记录 NOT_APPLICABLE 而不伪造 CLEAR，也不静默关闭助手', (tester) async {
      final intentEvents = <String>[];
      final traceEvents = <AiTraceEvent>[];
      final service = _OrderedIntentSendService(intentEvents);
      final recorder = AiTraceRecorder(
        enabled: true,
        writer: (event) async => traceEvents.add(event),
        idFactory: () => 'cccccccccccccccccccccccccccccccc',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(
            conversationStore: _store,
            service: service,
            imagePicker: _EmptyLocalAiImagePicker(),
            traceRecorder: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0;
          attempt < 50 && find.byTooltip('释放模型内存').evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byTooltip('释放模型内存'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '我想排盘');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(intentEvents, ['intent']);
      expect(service.intentQueries, ['我想排盘']);
      final redFlagEvent = traceEvents.singleWhere(
        (event) => event.stage == AiTraceStage.redFlag,
      );
      expect(redFlagEvent.status, AiTraceStatus.notApplicable);
      expect(redFlagEvent.errorCode, 'REDFLAG_GATE_NOT_CONFIGURED');
      expect(
        traceEvents.where((event) => event.stage == AiTraceStage.redFlag)
            .every((event) => event.status != AiTraceStatus.succeeded),
        isTrue,
      );
    });

  });
}

