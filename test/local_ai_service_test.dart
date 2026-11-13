import 'dart:convert';

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

    test('resolveAssistantIntent sends a bounded candidate set and validates the selected ID', () async {
      const traceId = '0123456789abcdef0123456789abcdef';
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'decision': '{"action":"select","tool_id":"bazi"}',
          'backend': 'cpu',
          'trace_id': traceId,
        };
      });

      final result = await LocalAiService().resolveAssistantIntentWithTrace(
        query: '按出生资料看看传统命盘',
        candidates: const [
          LocalAiIntentCandidate(
            id: 'ziwei',
            title: '紫微斗数',
            description: '调用 App 原有紫微排盘。',
          ),
          LocalAiIntentCandidate(
            id: 'bazi',
            title: '八字四柱',
            description: '调用 App 原有八字排盘。',
          ),
        ],
        traceId: traceId,
      );

      expect(received?.method, 'resolveAssistantIntent');
      expect(received?.arguments, <String, Object?>{
        'text': '按出生资料看看传统命盘',
        'candidates': '[{"id":"ziwei","title":"紫微斗数","description":"调用 App 原有紫微排盘。"},{"id":"bazi","title":"八字四柱","description":"调用 App 原有八字排盘。"}]',
        'trace_id': traceId,
      });
      expect(result.action, LocalAiIntentAction.select);
      expect(result.toolId, 'bazi');
      expect(result.backend, 'cpu');
    });

    test('resolveAssistantIntent keeps clarification as a non-dispatch result', () async {
      const traceId = '0123456789abcdef0123456789abcdef';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{
          'decision': '{"action":"clarify","tool_id":null}',
          'backend': 'gpu',
          'trace_id': traceId,
        },
      );

      final result = await LocalAiService().resolveAssistantIntentWithTrace(
        query: '帮我看一下',
        candidates: const [
          LocalAiIntentCandidate(
            id: 'ziwei',
            title: '紫微斗数',
            description: '紫微排盘。',
          ),
          LocalAiIntentCandidate(
            id: 'bazi',
            title: '八字四柱',
            description: '八字排盘。',
          ),
        ],
        traceId: traceId,
      );

      expect(result.action, LocalAiIntentAction.clarify);
      expect(result.toolId, isNull);
      expect(result.backend, 'gpu');
    });

    test('resolveAssistantIntent rejects candidate IDs outside the supplied set', () async {
      const traceId = '0123456789abcdef0123456789abcdef';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{
          'decision': '{"action":"select","tool_id":"dosage"}',
          'backend': 'cpu',
          'trace_id': traceId,
        },
      );

      await expectLater(
        LocalAiService().resolveAssistantIntentWithTrace(
          query: '按出生资料排盘',
          candidates: const [
            LocalAiIntentCandidate(
              id: 'ziwei',
              title: '紫微斗数',
              description: '紫微排盘。',
            ),
            LocalAiIntentCandidate(
              id: 'bazi',
              title: '八字四柱',
              description: '八字排盘。',
            ),
          ],
          traceId: traceId,
        ),
        throwsFormatException,
      );
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

  group('LocalAiIntentResolution schema', () {
    test('accepts only exact select, clarify, and none actions', () {
      final selected = LocalAiIntentResolution.fromModelText(
        '{"action":"select","tool_id":"bazi"}',
      );
      expect(selected.action, LocalAiIntentAction.select);
      expect(selected.toolId, 'bazi');

      final clarify = LocalAiIntentResolution.fromModelText(
        '{"action":"clarify","tool_id":null}',
      );
      expect(clarify.action, LocalAiIntentAction.clarify);
      expect(clarify.toolId, isNull);

      final none = LocalAiIntentResolution.fromModelText(
        '{"action":"none","tool_id":null}',
      );
      expect(none.action, LocalAiIntentAction.none);
      expect(none.toolId, isNull);
    });

    test('rejects extra fields, invented IDs, malformed JSON, and oversized output', () {
      for (final payload in <String>[
        '{"action":"select","tool_id":"bazi","arguments":{"date":"today"}}',
        '{"action":"select","tool_id":"not a tool"}',
        '{"action":"delete","tool_id":null}',
        'not json',
        '{"action":"select","tool_id":"${List<String>.filled(2100, 'a').join()}"}',
      ]) {
        expect(
          () => LocalAiIntentResolution.fromModelText(payload),
          throwsFormatException,
          reason: payload.length > 80 ? 'oversized payload' : payload,
        );
      }
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

  group('LocalAiService trace ID bridge contract', () {
    const traceId = '0123456789abcdef0123456789abcdef';

    test('sendMessage forwards trace ID and requires an exact native echo', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'reply': '继续描述',
          'trace_id': traceId,
        };
      });

      final reply = await LocalAiService().sendMessageWithTrace(
        '继续问诊',
        traceId: traceId,
      );

      expect(reply, '继续描述');
      expect(received?.arguments, <String, Object?>{
        'text': '继续问诊',
        'trace_id': traceId,
      });
    });

    test('sendMessageWithContextAndTrace preserves context and correlation ID', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'reply': '依据本地资料整理',
          'trace_id': traceId,
        };
      });

      final reply = await LocalAiService().sendMessageWithContextAndTrace(
        '柴胡的传统功用是什么？',
        context: '[App本草库] 柴胡：原始条目',
        traceId: traceId,
      );

      expect(reply, '依据本地资料整理');
      expect(received?.arguments, <String, Object?>{
        'text': '柴胡的传统功用是什么？',
        'context': '[App本草库] 柴胡：原始条目',
        'trace_id': traceId,
      });
    });

    test('sendMessage rejects a mismatched native trace ID', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{
          'reply': '回答',
          'trace_id': 'ffffffffffffffffffffffffffffffff',
        },
      );

      await expectLater(
        LocalAiService().sendMessageWithTrace('继续问诊', traceId: traceId),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'TRACE_ID_MISMATCH',
          ),
        ),
      );
    });

    test('image and audio calls forward and validate trace ID', () async {
      final received = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        received.add(call);
        return <String, Object?>{
          'reply': '附件分析',
          'trace_id': traceId,
        };
      });

      await LocalAiService().sendImageWithTrace(
        '/app/cache/tongue.jpg',
        traceId: traceId,
      );
      await LocalAiService().sendAudioWithTrace(
        '/app/cache/interview.wav',
        traceId: traceId,
      );

      expect(received.map((call) => call.method), ['sendImage', 'sendAudio']);
      expect(received[0].arguments['trace_id'], traceId);
      expect(received[1].arguments['trace_id'], traceId);
    });

    test('extractSymptomsWithTrace forwards and validates trace ID', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'draft': '{"main_complaint":"头痛"}',
          'sourceTruncated': false,
          'trace_id': traceId,
        };
      });

      final draft = await LocalAiService().extractSymptomsWithTrace(
        traceId: traceId,
      );

      expect(draft.mainComplaint, '头痛');
      expect(received?.method, 'extractSymptoms');
      expect(received?.arguments, <String, Object?>{
        'trace_id': traceId,
      });
    });

    test('Bazi slot extraction sends only missing fields and returns evidenced values', () async {
      const traceId = '0123456789abcdef0123456789abcdef';
      const query = '我在上海市出生，生日是1990年1月2日，早上八点半，男性';
      final rawDraft = jsonEncode({
        'birth_date': {'value': null, 'evidence': null},
        'birth_time': {'value': '08:30', 'evidence': '早上八点半'},
        'gender': {'value': null, 'evidence': null},
        'birthplace': {'value': '上海市', 'evidence': '在上海市出生'},
      });
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, Object?>{
          'draft': rawDraft,
          'backend': 'cpu',
          'trace_id': traceId,
        };
      });

      final draft = await LocalAiService().extractBaziSlotsWithTrace(
        query: query,
        missingKeys: const {'birth_time', 'birthplace'},
        traceId: traceId,
      );

      expect(received?.method, 'extractBaziSlots');
      expect(received?.arguments, <String, Object?>{
        'text': query,
        'missing_fields': '["birth_time","birthplace"]',
        'trace_id': traceId,
      });
      expect(draft.values, const {
        'birth_time': '08:30',
        'birthplace': '上海市',
      });
      expect(draft.backend, 'cpu');
    });

    test("Bazi slot evidence rejects values that do not match the user's words", () {
      const query = '我出生时是早上八点半，在上海市出生';
      final rawDraft = jsonEncode({
        'birth_date': {'value': null, 'evidence': null},
        'birth_time': {'value': '09:30', 'evidence': '早上八点半'},
        'gender': {'value': null, 'evidence': null},
        'birthplace': {'value': '上海市', 'evidence': '在上海市出生'},
      });

      expect(
        () => LocalAiBaziSlotDraft.fromModelText(
          rawDraft,
          userText: query,
          requestedKeys: const {'birth_time', 'birthplace'},
        ),
        throwsFormatException,
      );
    });

    test('Bazi slot evidence cannot overwrite fields that deterministic code already supplied', () {
      const query = '出生日期1990年1月2日；早上八点半';
      final rawDraft = jsonEncode({
        'birth_date': {'value': '1990-01-02', 'evidence': '1990年1月2日'},
        'birth_time': {'value': '08:30', 'evidence': '早上八点半'},
        'gender': {'value': null, 'evidence': null},
        'birthplace': {'value': null, 'evidence': null},
      });

      expect(
        () => LocalAiBaziSlotDraft.fromModelText(
          rawDraft,
          userText: query,
          requestedKeys: const {'birth_time'},
        ),
        throwsFormatException,
      );
    });

    test('invalid trace ID is rejected before a platform call', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return <String, Object?>{'reply': 'must not be called'};
      });

      await expectLater(
        LocalAiService().sendMessageWithTrace('继续问诊', traceId: 'not-a-trace-id'),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, 0);
    });
  });

}
