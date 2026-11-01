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

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

  @override
  Future<String> sendMessage(String text) async {
    sentTexts.add(text);
    return '已收到你的描述：$text';
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
        '最近三天偶尔头痛，睡眠后会缓解。',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sentTexts, ['最近三天偶尔头痛，睡眠后会缓解。']);
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
              widget.data == '已收到你的描述：最近三天偶尔头痛，睡眠后会缓解。',
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

  testWidgets(
    'warns the user when symptom source history was truncated',
    (tester) async {
      final service = _SourceTruncatedSymptomsService();

      await tester.pumpWidget(
        MaterialApp(home: LocalAiInterviewScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '较早的头痛描述');
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
    'returns symptom summary to rule interview only after explicit confirmation',
    (tester) async {
      final service = _DraftTextService();

      await tester.pumpWidget(
        MaterialApp(home: _InterviewHandoffHost(service: service)),
      );

      await tester.tap(find.text('打开本地问诊'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '饭后腹胀，已经持续约两周。');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(service.sentTexts, ['饭后腹胀，已经持续约两周。']);
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
      await tester.tap(find.text('返回规则问诊'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('returned-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('主要不适：饭后腹胀'), findsOneWidget);
      expect(find.textContaining('持续时间：约两周'), findsOneWidget);
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
}
