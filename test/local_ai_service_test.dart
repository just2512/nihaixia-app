import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.nihaisha.app/local_ai');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('LocalAiService attachment channel contract', () {
    test('importModel returns native model installation status', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'installed': true,
          'fileExists': true,
          'ready': false,
          'modelPath': '/data/user/0/app/files/ai_models/gemma-4-E4B-it.litertlm',
          'sizeBytes': 3659530240,
          'expectedSizeBytes': 3659530240,
          'backend': 'not_loaded',
        };
      });

      final status = await LocalAiService().importModel();

      expect(received?.method, 'importModel');
      expect(status.installed, isTrue);
      expect(status.fileExists, isTrue);
      expect(status.ready, isFalse);
      expect(status.sizeBytes, 3659530240);
    });

    test('sendImage passes cached path and user prompt to native channel', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{'reply': '舌体可见特征描述'};
      });

      final reply = await LocalAiService().sendImage(
        '/app/cache/tongue.jpg',
        prompt: '请说明照片是否清晰',
      );

      expect(reply, '舌体可见特征描述');
      expect(received?.method, 'sendImage');
      expect(received?.arguments, <String, Object?>{
        'path': '/app/cache/tongue.jpg',
        'prompt': '请说明照片是否清晰',
      });
    });

    test('sendAudio passes cached path and user prompt to native channel', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{'reply': '用户语音转写内容'};
      });

      final reply = await LocalAiService().sendAudio(
        '/app/cache/interview.wav',
        prompt: '请保留听不清的部分',
      );

      expect(reply, '用户语音转写内容');
      expect(received?.method, 'sendAudio');
      expect(received?.arguments, <String, Object?>{
        'path': '/app/cache/interview.wav',
        'prompt': '请保留听不清的部分',
      });
    });

    test('attachment calls reject empty native replies', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{'reply': '  '},
      );

      await expectLater(
        LocalAiService().sendImage('/app/cache/tongue.jpg'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        LocalAiService().sendAudio('/app/cache/interview.wav'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('LocalAiModelStatus', () {
    test('reads installed model and active backend', () {
      final status = LocalAiModelStatus.fromMap({
        'installed': true,
        'ready': true,
        'fileExists': true,
        'modelPath': '/data/user/0/app/files/ai_models/gemma-4-E4B-it.litertlm',
        'sizeBytes': 3659530240,
        'expectedSizeBytes': 3659530240,
        'backend': 'gpu',
      });

      expect(status.installed, isTrue);
      expect(status.fileExists, isTrue);
      expect(status.ready, isTrue);
      expect(status.backend, 'gpu');
      expect(status.sizeLabel, '3.66 GB');
      expect(status.modelPath, contains('gemma-4-E4B-it.litertlm'));
    });

    test('uses safe defaults when native fields are missing', () {
      final status = LocalAiModelStatus.fromMap(const {});

      expect(status.installed, isFalse);
      expect(status.fileExists, isFalse);
      expect(status.ready, isFalse);
      expect(status.modelPath, isEmpty);
      expect(status.sizeBytes, 0);
      expect(status.expectedSizeBytes, 3659530240);
      expect(status.backend, 'not_loaded');
      expect(status.sizeLabel, '尚未安装');
    });

    test('parses a user-reported symptom draft and ignores unsupported fields', () {
      final draft = LocalAiSymptomDraft.fromModelText('''
```json
{
  "main_complaint": "饭后腹胀",
  "onset": "两周前",
  "duration": "每天饭后约一小时",
  "location": "上腹部",
  "sensation": "胀满",
  "aggravating_factors": ["吃得过饱"],
  "relieving_factors": ["散步后稍缓解"],
  "associated_symptoms": ["嗳气"],
  "red_flags": [],
  "unknowns": ["是否与某种食物有关"],
  "diagnosis": "不应接受"
}
```
''');

      expect(draft.mainComplaint, '饭后腹胀');
      expect(draft.onset, '两周前');
      expect(draft.aggravatingFactors, ['吃得过饱']);
      expect(draft.associatedSymptoms, ['嗳气']);
      expect(draft.unknowns, ['是否与某种食物有关']);
      expect(draft.summaryLines.join('、'), contains('饭后腹胀'));
      expect(draft.summaryLines.join('、'), isNot(contains('不应接受')));
    });

    test('rejects malformed model symptom output', () {
      expect(
        () => LocalAiSymptomDraft.fromModelText('not json'),
        throwsFormatException,
      );
    });

    test('does not report a model as installed for an empty file', () {
      final status = LocalAiModelStatus.fromMap({
        'installed': false,
        'ready': false,
        'sizeBytes': 0,
      });

      expect(status.installed, isFalse);
      expect(status.ready, isFalse);
      expect(status.sizeLabel, '尚未安装');
    });
  });
}
