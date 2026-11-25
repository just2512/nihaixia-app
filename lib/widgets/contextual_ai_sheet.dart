import 'package:flutter/material.dart';

import '../data/assistant_conversation_store.dart';
import '../models/ai_context_ref.dart';
import '../screens/assistant_tool_router.dart';
import '../screens/local_ai_interview_screen.dart';
import '../utils/fold_aware_routes.dart';

/// Optional persistence boundary for contextual assistant hosts. The app
/// defaults to its normal SQLite-backed conversation store; a host may provide
/// a scoped store for deterministic tests or an alternate app shell.
class ContextualAiConversationStoreScope extends InheritedWidget {
  const ContextualAiConversationStoreScope({
    super.key,
    required this.conversationStore,
    required super.child,
  });

  final AssistantConversationStore conversationStore;

  static AssistantConversationStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<
          ContextualAiConversationStoreScope>()?.conversationStore;

  @override
  bool updateShouldNotify(ContextualAiConversationStoreScope oldWidget) =>
      !identical(conversationStore, oldWidget.conversationStore);
}

/// Selects the contextual assistant presentation from the available window width.
bool usesContextualSidePanel(double availableWidth) => availableWidth >= 720;

/// Width of the side panel, bounded to remain useful on foldable and desktop windows.
double contextualSidePanelWidth(double availableWidth) =>
    (availableWidth * 0.4).clamp(340.0, 520.0).toDouble();

typedef ContextualAiAssistantBuilder = Widget Function(
  ScrollController? scrollController,
);

/// Shared content shell for the contextual assistant's two window presentations.
///
/// Kept separate from route creation so the actual bottom-sheet and side-panel
/// layouts can be widget-tested at the Find N2 outer/inner window sizes.
class ContextualAiPanel extends StatelessWidget {
  const ContextualAiPanel({
    super.key,
    required this.sidePanel,
    required this.panelWidth,
    required this.panelHeight,
    required this.assistantBuilder,
  });

  final bool sidePanel;
  final double panelWidth;
  final double panelHeight;
  final ContextualAiAssistantBuilder assistantBuilder;

  @override
  Widget build(BuildContext context) {
    final panelMediaQuery = MediaQuery.of(context);
    final keyboardInset = panelMediaQuery.viewInsets.bottom;
    final keyboardVisible = keyboardInset > 0;

    if (sidePanel) {
      // Dialog already animates its own outer padding by viewInsets. Do not
      // wrap it in a second IME padding layer. Re-expose the original inset to
      // the assistant after Dialog removes it internally, so the assistant can
      // hide nonessential header content without resizing its Scaffold again.
      return Dialog(
        alignment: Alignment.centerRight,
        insetPadding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (dialogContext, constraints) {
            final contentHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                    .clamp(0.0, panelHeight)
                    .toDouble()
                : panelHeight;
            return MediaQuery(
              data: MediaQuery.of(dialogContext).copyWith(
                viewInsets: panelMediaQuery.viewInsets,
              ),
              child: SizedBox(
                key: const ValueKey('contextual-ai-panel-content'),
                width: panelWidth,
                height: contentHeight,
                child: assistantBuilder(null),
              ),
            );
          },
        ),
      );
    }

    // The modal bottom-sheet route itself does not resize this draggable child
    // for the IME. Move the whole sheet above the keyboard at this boundary.
    // The inner assistant Scaffold stays resizeToAvoidBottomInset=false, so
    // this is the only resize operation on the contextual sheet path.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: keyboardVisible ? 0.95 : 0.82,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (sheetContext, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: assistantBuilder(scrollController),
        ),
      ),
    );
  }}

/// Presents the existing assistant inside a foldable, in-page contextual sheet.
/// The assistant screen owns model execution and conversation persistence.
Future<void> showContextualAiSheet({
  required BuildContext context,
  required AiContextRef contextRef,
  String? initialPrompt,
  String? initialUserMessage,
  bool autoSendInitialMessage = false,
  bool resolveContextualKnowledgeEntry = false,
  required AssistantMode initialMode,
  String? contextualTitle,
  bool contextualExplanationOnly = true,
}) {
  final restoredContextRef = AiContextRef.fromMetadata(contextRef.toMetadata());
  final normalizedRef = restoredContextRef?.toMetadata() ?? const <String, String>{};
  if (restoredContextRef == null || normalizedRef.isEmpty) {
    throw ArgumentError('A contextual AI sheet requires a stable context reference.');
  }

  Widget buildAssistant(ScrollController? scrollController) =>
      LocalAiInterviewScreen(
        key: ValueKey(
          contextRef.fieldPath == null
              ? (contextRef.snapshotId ?? contextRef.anchorId)
              : '${contextRef.snapshotId ?? contextRef.anchorId}:${contextRef.fieldPath}',
        ),
        initialPrompt: initialPrompt,
        initialUserMessage: initialUserMessage,
        autoSendInitialMessage: autoSendInitialMessage,
        resolveContextualKnowledgeEntry: resolveContextualKnowledgeEntry,
        initialMode: initialMode,
        contextualTitle: contextualTitle,
        contextualExplanationOnly: contextualExplanationOnly,
        conversationStore:
            ContextualAiConversationStoreScope.maybeOf(context),
        contextRef: normalizedRef,
        sheetScrollController: scrollController,
      );

  final windowSize = MediaQuery.sizeOf(context);
  final sidePanel = usesContextualSidePanel(windowSize.width);
  final panelWidth = contextualSidePanelWidth(windowSize.width);
  final panelHeight = (windowSize.height - 24).clamp(320.0, 2000.0).toDouble();

  if (sidePanel) {
    return showFoldAwareDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ContextualAiPanel(
        sidePanel: true,
        panelWidth: panelWidth,
        panelHeight: panelHeight,
        assistantBuilder: buildAssistant,
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => ContextualAiPanel(
      sidePanel: false,
      panelWidth: panelWidth,
      panelHeight: panelHeight,
      assistantBuilder: buildAssistant,
    ),
  );
}
