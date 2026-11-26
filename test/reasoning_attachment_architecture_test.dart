import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all assistant attachments enter the typed Core-3 reasoning contract', () {
    final screen = File('lib/screens/local_ai_interview_screen.dart').readAsStringSync();
    final service = File('lib/services/local_ai_service.dart').readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt',
    ).readAsStringSync();
    final request = File('lib/models/reasoning_request.dart').readAsStringSync();
    final codec = File('lib/services/reasoning_response_codec.dart').readAsStringSync();
    final actionAdapter = File('lib/services/reasoning_action_proposal_adapter.dart').readAsStringSync();

    expect(screen, contains('ReasoningAttachmentType? attachmentType'));
    expect(screen, contains('attachmentType: audioPath != null'));
    expect(screen, contains('_service.sendReasoningAttachmentMessage('));
    expect(screen, contains('_service.sendReasoningAttachmentMessageWithTrace('));
    expect(screen, isNot(contains('_service.sendImage(')));
    expect(screen, isNot(contains('_service.sendAudio(')));

    // Audit every production Dart caller, not only the main assistant screen.
    // LocalAiService keeps old compatibility methods for source compatibility,
    // but no production route may invoke their unstructured Native endpoints.
    final legacyMediaCall = RegExp(r'\\.\\s*send(?:Image|Audio)\\s*\\(');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart') ||
          entity.path == 'lib/services/local_ai_service.dart') {
        continue;
      }
      expect(
        legacyMediaCall.hasMatch(entity.readAsStringSync()),
        isFalse,
        reason: 'Unstructured legacy media call remains in ${entity.path}',
      );
    }

    // The selected mode remains App-owned. Tool mode uses its separate
    // proposal adapter but must carry the same typed attachment metadata.
    expect(screen, contains('case AssistantMode.automatic:'));
    expect(screen, contains('case AssistantMode.consultation:'));
    expect(screen, contains('case AssistantMode.learning:'));
    expect(screen, contains('case AssistantMode.tools:'));
    expect(screen, contains('case AssistantMode.metaphysics:'));
    expect(actionAdapter, contains('expectedAttachmentType: request.attachmentType?.name'));
    expect(actionAdapter, contains('attachmentType: attachmentType'));
    expect(screen, contains('attachmentType: attachmentType'));
    expect(screen, contains('currentRequest.attachmentType != null'));

    expect(request, contains('enum ReasoningAttachmentType { image, audio }'));
    expect(request, contains('attachmentPromptGenerated'));
    expect(codec, contains('_parseAttachmentResult'));
    expect(codec, contains('REASONING_RESPONSE_ATTACHMENT_RESULT_INVALID_OR_MISMATCHED'));
    expect(codec, contains('payload.containsKey(\'attachmentResult\')'));

    // Native uses the existing serial queue and the sole AI access gate.
    final handlerStart = native.indexOf('"sendReasoningAttachmentMessage" -> {');
    final handlerEnd = native.indexOf('"finalizeReasoningTurn" -> {', handlerStart);
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = native.substring(handlerStart, handlerEnd);
    expect(handler, contains('runAiTask(result, requiresAiAccess = true)'));
    expect(handler, contains('sendLocalReasoningAttachmentMessage('));

    final nativeMethodStart = native.indexOf('private fun sendLocalReasoningAttachmentMessage(');
    final nativeMethodEnd = native.indexOf('\n    private fun ', nativeMethodStart + 1);
    expect(nativeMethodStart, greaterThanOrEqualTo(0));
    final nativeMethod = native.substring(
      nativeMethodStart,
      nativeMethodEnd < 0 ? native.length : nativeMethodEnd,
    );
    expect(nativeMethod, contains('Content.ImageFile('));
    expect(nativeMethod, contains('Content.AudioFile('));
    expect(nativeMethod, contains('commitToHistory = false'));
    expect(nativeMethod, contains('preserveRawReply = true'));
    expect(nativeMethod, contains('createPendingTurn('));

    // Legacy channels fail closed instead of committing free-form media output.
    expect(native, contains('STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED'));
    final imageHandler = native.substring(
      native.indexOf('"sendImage" ->'),
      native.indexOf('"sendAudio" ->'),
    );
    final audioHandler = native.substring(
      native.indexOf('"sendAudio" ->'),
      native.indexOf('"sendReasoningMessage" ->'),
    );
    expect(imageHandler, contains('STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED'));
    expect(audioHandler, contains('STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED'));
    expect(service, contains('sendReasoningAttachmentMessageWithTrace'));
  });
}
