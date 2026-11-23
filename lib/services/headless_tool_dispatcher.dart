import 'dart:async';

import '../models/assistant_tool_result.dart';
import '../screens/assistant_tool_router.dart';

/// The only application boundary that invokes a registered Headless executor.
///
/// Argument extraction and validation remain in the caller during F0. The
/// dispatcher deliberately has no BuildContext, navigation, trace, persistence,
/// or UI responsibilities; it only resolves and invokes the executor once.
class HeadlessToolDispatcher {
  const HeadlessToolDispatcher._();

  static Future<AssistantToolResult> execute({
    required AssistantToolDefinition tool,
    required Map<String, String> arguments,
    FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
        executorOverride,
  }) async {
    final executor = executorOverride ?? tool.headlessExecutor;
    if (executor == null) {
      throw StateError(
        'Tool "${tool.id}" does not register a Headless executor.',
      );
    }
    return await executor(arguments);
  }
}
