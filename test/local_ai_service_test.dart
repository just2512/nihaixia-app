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
          'hashVerified': true,
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
      expect(status.hashVerified, isTrue);
      expect(status.ready, isFalse);
      expect(status.sizeBytes, 3659530240);
    });

    test('clearAiData invokes native cleanup and keeps the installed model', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'installed': true,
          'fileExists': true,
          'hashVerified': true,
          'ready': false,
          'modelPath': '/app/files/ai_models/gemma-4-E4B-it.litertlm',
          'sizeBytes': 3659530240,
          'expectedSizeBytes': 3659530240,
          'backend': 'not_loaded',
          'deletedRuntimeFiles': 4,
          'deletedAttachmentFiles': 2,
        };
      });

      final status = await LocalAiService().clearAiData();

      expect(received?.method, 'clearAiData');
      expect(status.installed, isTrue);
      expect(status.ready, isFalse);
      expect(status.backend, 'not_loaded');
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

    test('attachment calls reject null, blank, and non-string native replies', () async {
      final invalidResponses = <Object?>[
        null,
        <String, Object?>{},
        <String, Object?>{'reply': null},
        <String, Object?>{'reply': '  '},
        <String, Object?>{'reply': 42},
      ];

      for (final response in invalidResponses) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => response,
        );

        await expectLater(
          LocalAiService().sendImage('/app/cache/tongue.jpg'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'EMPTY_REPLY',
            ),
          ),
        );
        await expectLater(
          LocalAiService().sendAudio('/app/cache/interview.wav'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'EMPTY_REPLY',
            ),
          ),
        );
      }
    });
  });

  group('LocalAiService text conversation contract', () {
    test('sendMessage forwards the exact user text and returns native reply', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{'reply': '请继续描述不适出现的时间'};
      });

      final reply = await LocalAiService().sendMessage('饭后腹胀，持续两周');

      expect(received?.method, 'sendMessage');
      expect(received?.arguments, <String, Object?>{
        'text': '饭后腹胀，持续两周',
      });
      expect(reply, '请继续描述不适出现的时间');
    });


    test('sendMessageWithContext separates user text from retrieved knowledge context', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{'reply': '依据本地资料整理的回答'};
      });

      final reply = await LocalAiService().sendMessageWithContext(
        '柴胡的传统功用是什么？',
        context: '[App本草库] 柴胡：原始条目内容',
      );

      expect(reply, '依据本地资料整理的回答');
      expect(received?.method, 'sendMessage');
      expect(received?.arguments, <String, Object?>{
        'text': '柴胡的传统功用是什么？',
        'context': '[App本草库] 柴胡：原始条目内容',
      });
    });

    test('sendMessage rejects missing, null, and whitespace-only native replies', () async {
      final invalidResponses = <Object?>[
        <String, Object?>{},
        <String, Object?>{'reply': null},
        <String, Object?>{'reply': '   '},
      ];

      for (final response in invalidResponses) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => response,
        );
        await expectLater(
          LocalAiService().sendMessage('继续问诊'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'EMPTY_REPLY',
            ),
          ),
        );
      }
    });

    test('sendMessage rejects non-string native replies with a contract error', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{'reply': 42},
      );

      await expectLater(
        LocalAiService().sendMessage('继续问诊'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'EMPTY_REPLY',
          ),
        ),
      );
    });


    test('restoreConversation forwards bounded history and user-only turns', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{'restored': true, 'backend': 'cpu'};
      });

      await LocalAiService().restoreConversation(
        transcript: '用户：饭后腹胀\\n助手：请说明持续时间',
        userMessages: ['饭后腹胀'],
      );

      expect(received?.method, 'restoreConversation');
      expect(received?.arguments, <String, Object?>{
        'transcript': '用户：饭后腹胀\\n助手：请说明持续时间',
        'userMessages': ['饭后腹胀'],
      });
    });

    test('resetConversation invokes native reset and returns fresh status', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'installed': true,
          'fileExists': true,
          'ready': true,
          'modelPath': '/app/files/ai_models/gemma-4-E4B-it.litertlm',
          'sizeBytes': 3659530240,
          'expectedSizeBytes': 3659530240,
          'backend': 'cpu',
        };
      });

      final status = await LocalAiService().resetConversation();

      expect(received?.method, 'resetConversation');
      expect(status.ready, isTrue);
      expect(status.backend, 'cpu');
    });

    test('extractSymptoms invokes its isolated native operation and parses draft', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'draft': '{"main_complaint":"饭后腹胀","unknowns":["开始时间待确认"]}',
          'sourceTruncated': true,
        };
      });

      final draft = await LocalAiService().extractSymptoms();

      expect(received?.method, 'extractSymptoms');
      expect(draft.mainComplaint, '饭后腹胀');
      expect(draft.unknowns, ['开始时间待确认']);
      expect(draft.sourceTruncated, isTrue);
    });

    test('extractSymptoms rejects missing source truncation metadata', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{
          'draft': '{"main_complaint":"头痛"}',
        },
      );

      await expectLater(
        LocalAiService().extractSymptoms(),
        throwsFormatException,
      );
    });

    test('extractSymptoms rejects non-boolean source truncation metadata', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{
          'draft': '{"main_complaint":"头痛"}',
          'sourceTruncated': 'true',
        },
      );

      await expectLater(
        LocalAiService().extractSymptoms(),
        throwsFormatException,
      );
    });
    test('extractSymptoms rejects missing draft payload', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{},
      );

      await expectLater(
        LocalAiService().extractSymptoms(),
        throwsFormatException,
      );
    });

    test('extractSymptoms rejects non-string draft payload', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{'draft': 42},
      );

      await expectLater(
        LocalAiService().extractSymptoms(),
        throwsFormatException,
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
      expect(status.hashVerified, isFalse);
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

    test('rejects oversized model symptom payload before parsing JSON', () {
      final oversizedValue = List<String>.filled(16000, 'x').join();
      final payload = '{"main_complaint":"$oversizedValue"}';

      expect(
        () => LocalAiSymptomDraft.fromModelText(payload),
        throwsFormatException,
      );
    });

    test('rejects an oversized scalar symptom field', () {
      final oversizedField = List<String>.filled(501, 'x').join();
      final payload = '{"main_complaint":"$oversizedField"}';

      expect(
        () => LocalAiSymptomDraft.fromModelText(payload),
        throwsFormatException,
      );
    });

    test('rejects symptom lists with too many entries', () {
      final values = List<String>.filled(21, '症状').map((item) => '"$item"').join(',');
      final payload = '{"unknowns":[$values]}';

      expect(
        () => LocalAiSymptomDraft.fromModelText(payload),
        throwsFormatException,
      );
    });

    test('rejects an overlong symptom list item', () {
      final item = List<String>.filled(301, 'x').join();
      final payload = '{"unknowns":["$item"]}';

      expect(
        () => LocalAiSymptomDraft.fromModelText(payload),
        throwsFormatException,
      );
    });

    test('rejects oversized model symptom payload before parsing JSON', () {
      final oversizedValue = List<String>.filled(16000, 'x').join();
      final payload = '{"main_complaint":"$oversizedValue"}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
    });

    test('rejects an oversized scalar symptom field', () {
      final oversizedField = List<String>.filled(501, 'x').join();
      final payload = '{"main_complaint":"$oversizedField"}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
    });

    test('rejects symptom lists with too many entries', () {
      final values = List<String>.filled(21, '症状').map((item) => '"$item"').join(',');
      final payload = '{"unknowns":[$values]}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
    });

    test('rejects an overlong symptom list item', () {
      final item = List<String>.filled(301, 'x').join();
      final payload = '{"unknowns":["$item"]}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
    });

    test('rejects a non-text scalar symptom field instead of dropping it', () {
      const payload = '{"main_complaint":123}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
    });

    test('rejects a non-list value for a symptom list field', () {
      const payload = '{"unknowns":"需要再次确认"}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
    });

    test('rejects non-text entries in symptom lists instead of dropping them', () {
      const payload = '{"unknowns":["需要再次确认",false]}';
      expect(() => LocalAiSymptomDraft.fromModelText(payload), throwsFormatException);
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
