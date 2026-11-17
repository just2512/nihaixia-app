import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

Widget _buildPanelTestApp({
  required Size size,
  required Brightness brightness,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(2.0),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: ContextualAiPanel(
        sidePanel: usesContextualSidePanel(size.width),
        panelWidth: contextualSidePanelWidth(size.width),
        panelHeight: (size.height - 24).clamp(320.0, 2000.0).toDouble(),
        assistantBuilder: (scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: const [
            Text('情境助手内容'),
            Text(
              '这一段较长的中文说明用于验证二倍字号下仍然能够换行、滚动，'
              '不会因为窄窗口或侧栏宽度而造成布局溢出。',
            ),
            SizedBox(height: 900),
          ],
        ),
      ),
    ),
  );
}

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

  for (final brightness in Brightness.values) {
    testWidgets(
      '402dp outer window renders the draggable bottom panel at 200% text '
      '(${brightness.name})',
      (tester) async {
        const size = Size(402, 844);
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          _buildPanelTestApp(size: size, brightness: brightness),
        );
        await tester.pumpAndSettle();

        expect(usesContextualSidePanel(size.width), isFalse);
        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);

        final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet),
        );
        expect(sheet.initialChildSize, 0.82);
        expect(sheet.minChildSize, 0.55);
        expect(sheet.maxChildSize, 0.95);
        expect(
          tester.widget<ListView>(find.byType(ListView)).controller,
          isNotNull,
          reason: 'The assistant list must use the draggable sheet controller',
        );
        expect(find.text('情境助手内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      '775dp inner window renders the bounded side panel at 200% text '
      '(${brightness.name})',
      (tester) async {
        const size = Size(775, 1000);
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          _buildPanelTestApp(size: size, brightness: brightness),
        );
        await tester.pumpAndSettle();

        expect(usesContextualSidePanel(size.width), isTrue);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).alignment,
          Alignment.centerRight,
        );

        final panelContent = tester.widget<SizedBox>(
          find.byKey(const ValueKey('contextual-ai-panel-content')),
        );
        expect(panelContent.width, 340.0);
        expect(panelContent.height, 976.0);
        expect(find.text('情境助手内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
}
