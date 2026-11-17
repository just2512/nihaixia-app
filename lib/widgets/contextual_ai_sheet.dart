import 'package:flutter/material.dart';

import '../models/ai_context_ref.dart';
import '../screens/assistant_tool_router.dart';
import '../screens/local_ai_interview_screen.dart';

/// Presents the existing assistant inside a foldable, in-page contextual sheet.
/// The assistant screen owns model execution and conversation persistence.
Future<void> showContextualAiSheet({
  required BuildContext context,
  required AiContextRef contextRef,
  required String initialPrompt,
  required AssistantMode initialMode,
  String? contextualTitle,
  bool contextualExplanationOnly = true,
}) {
  final normalizedRef = AiContextRef.normalizeMetadata(contextRef.toMetadata());
  if (normalizedRef.isEmpty) {
    throw ArgumentError('A contextual AI sheet requires a stable context reference.');
  }

  Widget buildAssistant({ScrollController? scrollController}) =>
      LocalAiInterviewScreen(
        key: ValueKey(contextRef.snapshotId ?? contextRef.anchorId),
        initialPrompt: initialPrompt,
        initialMode: initialMode,
        contextualTitle: contextualTitle,
        contextualExplanationOnly: contextualExplanationOnly,
        contextRef: normalizedRef,
        sheetScrollController: scrollController,
      );

  final windowSize = MediaQuery.sizeOf(context);
  final renderObject = context.findRenderObject();
  final anchorPoint = renderObject is RenderBox && renderObject.hasSize
      ? renderObject.localToGlobal(renderObject.size.center(Offset.zero))
      : null;
  if (windowSize.width >= 840) {
    // Wide windows retain the reading/result page as the main surface and
    // present the assistant as a right-side panel. Dialog's anchor follows
    // Flutter's fold-aware sub-screen selection for the invoking context.
    final panelWidth = (windowSize.width * 0.4)
        .clamp(340.0, 520.0)
        .toDouble();
    final panelHeight = (windowSize.height - 24).clamp(320.0, 2000.0).toDouble();
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      anchorPoint: anchorPoint,
      builder: (_) => Dialog(
        alignment: Alignment.centerRight,
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: panelWidth,
          height: panelHeight,
          child: buildAssistant(),
        ),
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
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (sheetContext, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: buildAssistant(scrollController: scrollController),
      ),
    ),
  );
}
