import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:nihaisha_app/data/assistant_conversation_store.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_attachment_storage.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

const _installedButReleased = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  hashVerified: true,
  ready: false,
  modelPath: '/app/files/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'not_loaded',
);

class _ClearAiService extends LocalAiService {
  _ClearAiService([this.events]);

  final List<String>? events;
  var clearCalls = 0;

  @override
  Future<LocalAiModelStatus> getStatus() async => _installedButReleased;

  @override
  Future<LocalAiModelStatus> clearAiData() async {
    clearCalls++;
    events?.add('native');
    return const LocalAiModelStatus(
      installed: true,
      fileExists: true,
      hashVerified: true,
      ready: false,
      modelPath: '/app/files/ai_models/gemma-4-E4B-it.litertlm',
      sizeBytes: 3659530240,
      expectedSizeBytes: 3659530240,
      backend: 'not_loaded',
      runtimeCacheFilesDeleted: 3,
      attachmentFilesDeleted: 2,
      legacyRecordingFilesDeleted: 1,
    );
  }
}

class _NoopAudioRecorder implements LocalAiAudioRecorder {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {}

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> dispose() async {}
}

class _MemoryAttachmentStorage extends LocalAiAttachmentStorage {
  _MemoryAttachmentStorage([this.events]);

  final List<String>? events;

  @override
  Future<int> clear() async {
    events?.add('attachments');
    return 0;
  }

  @override
  Future<int> clearLegacyRecordings() async {
    events?.add('legacy');
    return 0;
  }
}

class _NoLostImagePicker implements LocalAiImagePicker {
  @override
  Future<String?> pickCameraImagePath() async => null;

  @override
  Future<String?> retrieveLostImagePath() async => null;
}

class _MemoryConversationStore implements AssistantConversationStore {
  int _nextId = 1;
  final Map<int, Map<String, Object?>> _conversations = {};
  final Map<int, List<Map<String, Object?>>> _messages = {};
  final Map<int, TcmInterviewTaskState> _taskStates = {};

  @override
  Future<int> createAssistantConversation({
    String title = '新对话',
    String mode = 'general',
  }) async {
    final id = _nextId++;
    _conversations[id] = {'id': id, 'title': title, 'mode': mode};
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
    final messages = _messages.putIfAbsent(conversationId, () => []);
    messages.add({
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'metadata': metadata,
    });
    return messages.length;
  }

  @override
  Future<List<Map<String, Object?>>> getAssistantConversations({
    int? limit,
  }) async {
    final rows = _conversations.values.toList(growable: false);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clear-all action invokes native, attachment and conversation cleanup',
      (tester) async {
    final events = <String>[];
    final service = _ClearAiService(events);
    final store = _MemoryConversationStore();
    var conversationDataClearCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalAiInterviewScreen(
          service: service,
          audioRecorder: _NoopAudioRecorder(),
          conversationStore: store,
          imagePicker: _NoLostImagePicker(),
          attachmentStorage: _MemoryAttachmentStorage(events),
          aiConversationDataClearer: () async {
            events.add('database');
            conversationDataClearCalls++;
            return const {
              'assistantMessages': 2,
              'legacyChatMessages': 1,
              'assistantConversations': 1,
              'tcmInterviewTasks': 1,
            };
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('清除全部 AI 数据'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('清除全部 AI 数据？'), findsOneWidget);
    expect(find.textContaining('已导入的 Gemma 模型文件会保留'), findsOneWidget);

    await tester.tap(find.text('清除数据'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(service.clearCalls, 1);
    expect(conversationDataClearCalls, 1);
    expect(events, ['native', 'attachments', 'legacy', 'database']);
    expect(find.textContaining('你可以直接描述身体情况、询问中医知识'), findsOneWidget);
    expect(find.textContaining('AI 数据已清除'), findsOneWidget);
    expect(find.textContaining('推理缓存文件 3 个'), findsOneWidget);
  });
}
