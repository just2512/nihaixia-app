import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

void main() {
  test('contextual panel uses a bottom sheet below the wide-window breakpoint', () {
    expect(usesContextualSidePanel(402), isFalse);
    expect(usesContextualSidePanel(719), isFalse);
  });

  test('contextual panel switches to a side panel at the wide-window breakpoint', () {
    expect(usesContextualSidePanel(720), isTrue);
    expect(usesContextualSidePanel(1200), isTrue);
  });

  test('side panel width stays bounded for foldable and desktop windows', () {
    expect(contextualSidePanelWidth(720), 340.0);
    expect(contextualSidePanelWidth(775), 340.0);
    expect(contextualSidePanelWidth(1200), 480.0);
    expect(contextualSidePanelWidth(2400), 520.0);
  });
}
