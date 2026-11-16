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
}) {
  final normalizedRef = AiContextRef.normalizeMetadata(contextRef.toMetadata());
  if (normalizedRef.isEmpty) {
    throw ArgumentError('A contextual AI sheet requires a stable context reference.');
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
        child: LocalAiInterviewScreen(
          key: ValueKey(
            contextRef.snapshotId ?? contextRef.anchorId,
          ),
          initialPrompt: initialPrompt,
          initialMode: initialMode,
          contextRef: normalizedRef,
          sheetScrollController: scrollController,
        ),
      ),
    ),
  );
}
