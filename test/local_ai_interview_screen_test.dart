import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

const _readyStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: true,
  modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'cpu',
);

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
  });

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
        find.text('已收到你的描述：最近三天偶尔头痛，睡眠后会缓解。'),
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
      expect(find.text('重试成功：$userText'), findsOneWidget);
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
