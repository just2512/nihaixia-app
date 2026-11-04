import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';


const _readyStatus = LocalAiModelStatus(
  installed: true,
  fileExists: true,
  ready: true,
  modelPath: '/app/ai_models/gemma-4-E4B-it.litertlm',
  sizeBytes: 3659530240,
  expectedSizeBytes: 3659530240,
  backend: 'litert',
);

class _RecordingAssistantService extends LocalAiService {
  String? restoredTranscript;
  List<String> restoredUserMessages = const [];

  @override
  Future<LocalAiModelStatus> getStatus() async => _readyStatus;

  @override
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
  }) async => '已收到：$text';

  @override
  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
  }) async {
    restoredTranscript = transcript;
    restoredUserMessages = List<String>.from(userMessages);
  }
}

void main() {
  testWidgets('五运六气工具可把实际推算结果返回统一助手', (tester) async {
    String? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const YunQiScreen(returnResultOnComplete: true),
                  ),
                );
              },
              child: const Text('打开五运六气'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开五运六气'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('将本次推算结果带回助手对话'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('将本次推算结果带回助手对话'), findsOneWidget);

    await tester.tap(find.text('将本次推算结果带回助手对话'));
    await tester.pumpAndSettle();

    expect(returned, isNotNull);
    expect(returned, contains('推算日期：'));
    expect(returned, contains('岁运：'));
    expect(returned, contains('司天：'));
    expect(returned, contains('在泉：'));
    expect(returned, contains('口径：'));
    expect(returned!.split('\n').length, greaterThan(2));
    expect(returned, isNot(contains(r'\n')));
    expect(tester.takeException(), isNull);
  });


  testWidgets('五运六气结果回到统一时间线并同步进本地模型上下文', (tester) async {
    final service = _RecordingAssistantService();
    await tester.pumpWidget(
      MaterialApp(home: LocalAiInterviewScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我推算五运六气');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.text('打开五运六气推算'), findsOneWidget);

    await tester.tap(find.text('打开五运六气推算'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('将本次推算结果带回助手对话'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('将本次推算结果带回助手对话'));
    await tester.pumpAndSettle();

    expect(find.textContaining('【五运六气推算返回内容】'), findsOneWidget);
    expect(service.restoredTranscript, contains('司天：'));
    expect(service.restoredTranscript, contains('在泉：'));
    expect(service.restoredUserMessages, contains('帮我推算五运六气'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('从普通工具入口打开时不显示助手专用返回操作', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: YunQiScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('将本次推算结果带回助手对话'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
