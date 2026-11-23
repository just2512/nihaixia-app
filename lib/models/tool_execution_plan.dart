/// Origin of a tool execution plan.
///
/// A resumed task must carry the original value; it must never be inferred
/// from TRACE presence, widget state, call stack or the current page.
enum InvocationOrigin {
  userManual,
  aiDispatch,
}

/// One validated operation in a tool execution plan.
class ToolExecutionStep {
  ToolExecutionStep({
    required this.toolId,
    required this.capabilityId,
    required Map<String, String> arguments,
  })  : arguments = Map<String, String>.unmodifiable(arguments) {
    if (toolId.trim().isEmpty || toolId != toolId.trim()) {
      throw ArgumentError.value(toolId, 'toolId');
    }
    if (capabilityId.trim().isEmpty || capabilityId != capabilityId.trim()) {
      throw ArgumentError.value(capabilityId, 'capabilityId');
    }
    if (this.arguments.keys.any(
      (key) => key.trim().isEmpty || key != key.trim(),
    )) {
      throw ArgumentError.value(arguments, 'arguments');
    }
  }

  final String toolId;
  final String capabilityId;
  final Map<String, String> arguments;
}

/// Complete, immutable plan formed before the first business executor starts.
///
/// The plan intentionally does not execute tools or authorize features. It
/// provides a deterministic description that a dispatcher can validate as a
/// whole before any step can produce a business side effect.
class ToolExecutionPlan {
  ToolExecutionPlan({
    required this.planId,
    required this.origin,
    required List<ToolExecutionStep> steps,
  }) : steps = List<ToolExecutionStep>.unmodifiable(steps) {
    if (planId.trim().isEmpty || planId != planId.trim()) {
      throw ArgumentError.value(planId, 'planId');
    }
    if (this.steps.isEmpty) {
      throw ArgumentError.value(steps, 'steps', 'A plan must contain at least one step.');
    }
  }

  final String planId;
  final InvocationOrigin origin;
  final List<ToolExecutionStep> steps;

  /// Distinct business capabilities, not executor-call count.
  Set<String> get capabilityIds => Set<String>.unmodifiable(
        steps.map((step) => step.capabilityId),
      );

  /// Only AI-origin plans spanning multiple distinct business capabilities
  /// require ai_advanced. Repeated calls within one capability stay free.
  bool get requiresAdvancedAi =>
      origin == InvocationOrigin.aiDispatch && capabilityIds.length >= 2;
}
