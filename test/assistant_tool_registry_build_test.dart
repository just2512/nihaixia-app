import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';

void main() {
  test('registered utility tools construct their destination widgets', () {
    for (final tool in AssistantToolRouter.all) {
      if (tool.id == 'structured_diagnosis') {
        // Rule-based diagnosis is hosted inline in the unified conversation.
        expect(() => tool.builder(), throwsA(isA<StateError>()), reason: tool.id);
        continue;
      }
      expect(tool.builder(), isA<Widget>(), reason: tool.id);
    }
  });
}
