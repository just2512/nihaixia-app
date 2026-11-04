import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';
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

class _EmptyLocalAiImagePicker implements LocalAiImagePicker {
  @override
  Future<String?> retrieveLostImagePath() async => null;

  @override
  Future<String?> pickCameraImagePath() async => null;
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

class _TextSendService extends LocalAiService {
  final sentTexts = <String>[];
  final sentContexts = <String>[];

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

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
                  builder: (_) => LocalAiInterviewScreen(service: widget.service),
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

class _UnexpectedStatusFailureService extends LocalAiService {
  @override
  Future<LocalAiModelStatus> getStatus() async {
    throw StateError('status response was malformed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
            service: service,
            audioRecorder: recorder,
            recordingFileInspector: _ValidRecordingFileInspector(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('录制语音（最长 30 秒）'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('停止录音'), findsOneWidget);
      expect(recorder._path, isNotNull);

      await tester.tap(find.byTooltip('停止录音'));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 1);
      expect(find.textContaining('录音停止失败，录音可能仍在继续'), findsOneWidget);
      expect(find.byTooltip('停止录音'), findsOneWidget);

      await tester.tap(find.byTooltip('停止录音'));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 2);
      expect(find.text('语音已录制（最长 30 秒），发送前可移除。'), findsOneWidget);
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
          home: LocalAiInterviewScreen(
            service: _TextSendService(),
            audioRecorder: recorder,
            recordingFileInspector: _ThrowingRecordingFileInspector(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('录制语音（最长 30 秒）'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('停止录音'));
      await tester.pumpAndSettle();

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
          home: LocalAiInterviewScreen(service: service),
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

  testWidgets('问诊助手把本地中医知识作为参考上下文传给模型', (tester) async {
    final service = _TextSendService();
    await tester.pumpWidget(
      MaterialApp(home: LocalAiInterviewScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我最近三天口苦，胸闷');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.sentTexts, ['我最近三天口苦，胸闷']);
    expect(service.sentContexts, hasLength(1));
    expect(service.sentContexts.single, contains('当前角色：问诊助手'));
    expect(service.sentContexts.single, contains('App 本地知识库'));
    expect(service.sentContexts.single, contains('不自动诊断'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'warns the user when symptom source history was truncated',
    (tester) async {
      final service = _SourceTruncatedSymptomsService();

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          home: LocalAiInterviewScreen(
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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

      // 当前产品流程将已确认自述带入结构化辨证页面；自由文本只作上下文，
      // 不自动转换为辨证选项。
      expect(find.text('结构化辨证问诊'), findsOneWidget);
      expect(
        find.textContaining('主要不适：饭后腹胀'),
        findsOneWidget,
      );
      expect(find.textContaining('不自动映射为辨证选项'), findsOneWidget);

      Navigator.of(tester.element(find.text('结构化辨证问诊')))
          .pop('主要不适：饭后腹胀\n持续时间：约两周');
      await tester.pumpAndSettle();

      // 规则问诊结果回到统一 AI 会话时间线，不关闭会话或丢失历史。
      expect(
        find.textContaining('【结构化辨证问诊记录】'),
        findsOneWidget,
      );
      expect(find.textContaining('主要不适：饭后腹胀'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps failed text editable and retries without duplicate chat bubbles',
    (tester) async {
      final service = _FailOnceTextSendService();
      const userText = '昨晚开始咽喉不适，喝温水后稍有缓解。';

      await tester.pumpWidget(
        MaterialApp(
          home: LocalAiInterviewScreen(service: service),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), userText);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sendAttempts, 1);
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
          home: LocalAiInterviewScreen(
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
            home: LocalAiInterviewScreen(
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
            home: LocalAiInterviewScreen(
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
          MaterialApp(home: LocalAiInterviewScreen(service: service)),
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
      MaterialApp(home: LocalAiInterviewScreen(service: _TextSendService())),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动调度'), findsOneWidget);
    expect(
      find.textContaining('身体情况、询问中医知识'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
