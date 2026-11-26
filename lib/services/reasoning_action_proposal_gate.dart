import '../models/reasoning_response.dart';
import '../models/tool_execution_plan.dart';
import 'assistant_tool_execution_plan_builder.dart';
import 'dosage_tool_service.dart';
import 'headless_tool_dispatcher.dart';
import 'solar_term_tool_service.dart';

/// App-owned, request-scoped authorization boundary for Core-3 ACTION_PROPOSAL.
///
/// This policy does not execute tools. It validates an untrusted proposal,
/// returns an immutable preview for an App-owned confirmation surface, and
/// only creates a ToolExecutionPlan after explicit confirmation. The caller
/// must invoke HeadlessToolDispatcher separately after authorization.
class ReasoningActionProposalGate {
  const ReasoningActionProposalGate._();

  /// Executor registration is not enough. Only the existing four capabilities
  /// explicitly approved by AssistantToolExecutionPlanBuilder are supported.
  static const Map<String, String> _toolIdByCapabilityId = {
    'dosage': 'dosage',
    'solar_terms': 'solar_terms',
    'yuxiaji_omen': 'yuxiaji_omen',
    'sanshan_lingqian': 'sanshan_lingqian',
  };

  static Set<String> get supportedCapabilityIds =>
      Set<String>.unmodifiable(_toolIdByCapabilityId.keys);

  /// Validates the response against App-owned request scope and produces a
  /// confirmation preview. No executable plan is returned at this stage.
  static ReasoningActionProposalGateResult prepareForConfirmation({
    required ReasoningResponse response,
    required String expectedRequestId,
    required Set<String> requestCapabilityAllowlist,
  }) {
    final errors = _validate(
      response: response,
      expectedRequestId: expectedRequestId,
      requestCapabilityAllowlist: requestCapabilityAllowlist,
    );
    if (errors.isNotEmpty) return _rejected(errors);

    final proposal = response.actionProposal!;
    final toolId = _toolIdByCapabilityId[proposal.capabilityId]!;
    return ReasoningActionProposalGateResult._(
      status: ReasoningActionProposalGateStatus.confirmationRequired,
      preview: ReasoningActionProposalPreview._(
        requestId: response.requestId,
        proposalId: proposal.proposalId,
        capabilityId: proposal.capabilityId,
        toolId: toolId,
        arguments: proposal.arguments,
        requestCapabilityAllowlist: requestCapabilityAllowlist,
      ),
      errors: const [],
    );
  }

  /// Revalidates request identity and the complete capability allowlist after
  /// the confirmation UI returns. A changed scope invalidates the preview.
  /// The result contains a plan only when the user explicitly confirmed.
  static ReasoningActionProposalGateResult authorizeAfterConfirmation({
    required ReasoningActionProposalPreview preview,
    required String expectedRequestId,
    required Set<String> requestCapabilityAllowlist,
    required bool confirmedByUser,
  }) {
    if (!_isValidRequestId(expectedRequestId) ||
        preview.requestId != expectedRequestId) {
      return _rejected(const ['ACTION_PROPOSAL_REQUEST_ID_MISMATCH']);
    }
    if (!_sameSet(
      preview.requestCapabilityAllowlist,
      requestCapabilityAllowlist,
    )) {
      return _rejected(const ['ACTION_PROPOSAL_REQUEST_ALLOWLIST_CHANGED']);
    }

    final errors = _validateProposalFields(
      proposalId: preview.proposalId,
      capabilityId: preview.capabilityId,
      toolId: preview.toolId,
      arguments: preview.arguments,
      requestCapabilityAllowlist: preview.requestCapabilityAllowlist,
    );
    if (errors.isNotEmpty) return _rejected(errors);

    if (!confirmedByUser) {
      return ReasoningActionProposalGateResult._(
        status: ReasoningActionProposalGateStatus.declined,
        preview: preview,
        errors: const ['ACTION_PROPOSAL_USER_CONSENT_NOT_GRANTED'],
      );
    }

    // Prefix and 8-character request fragment keep planId <= 60 characters
    // even when proposalId uses its full 48-character allowance.
    final plan = ToolExecutionPlan(
      planId: 'rp-${preview.requestId.substring(0, 8)}-${preview.proposalId}',
      origin: InvocationOrigin.aiDispatch,
      steps: [
        ToolExecutionStep(
          toolId: preview.toolId,
          capabilityId: preview.capabilityId,
          arguments: preview.arguments,
        ),
      ],
    );
    return ReasoningActionProposalGateResult._(
      status: ReasoningActionProposalGateStatus.authorized,
      preview: preview,
      plan: plan,
      errors: const [],
    );
  }

  static List<String> _validate({
    required ReasoningResponse response,
    required String expectedRequestId,
    required Set<String> requestCapabilityAllowlist,
  }) {
    if (!_isValidRequestId(expectedRequestId) ||
        response.requestId != expectedRequestId) {
      return const ['ACTION_PROPOSAL_REQUEST_ID_MISMATCH'];
    }
    if (response.responseKind != ReasoningResponseKind.actionProposal ||
        response.status != ReasoningResponseStatus.completed ||
        response.actionProposal == null) {
      return const ['ACTION_PROPOSAL_RESPONSE_KIND_INVALID'];
    }

    final proposal = response.actionProposal!;
    final toolId = _toolIdByCapabilityId[proposal.capabilityId] ?? '';
    return _validateProposalFields(
      proposalId: proposal.proposalId,
      capabilityId: proposal.capabilityId,
      toolId: toolId,
      arguments: proposal.arguments,
      requestCapabilityAllowlist: requestCapabilityAllowlist,
    );
  }

  static List<String> _validateProposalFields({
    required String proposalId,
    required String capabilityId,
    required String toolId,
    required Map<String, String> arguments,
    required Set<String> requestCapabilityAllowlist,
  }) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$').hasMatch(proposalId)) {
      return const ['ACTION_PROPOSAL_ID_INVALID'];
    }
    if (!requestCapabilityAllowlist.contains(capabilityId)) {
      return const ['ACTION_PROPOSAL_CAPABILITY_NOT_ALLOWED_FOR_REQUEST'];
    }

    final expectedToolId = _toolIdByCapabilityId[capabilityId];
    if (expectedToolId == null || expectedToolId != toolId ||
        !AssistantToolExecutionPlanBuilder.supportsPlan(toolId)) {
      return const ['ACTION_PROPOSAL_CAPABILITY_NOT_PLAN_ELIGIBLE'];
    }
    if (!HeadlessToolDispatcher.hasExecutor(toolId) ||
        HeadlessToolDispatcher.capabilityIdForTool(toolId) != capabilityId) {
      return const ['ACTION_PROPOSAL_EXECUTOR_REGISTRATION_MISMATCH'];
    }

    switch (capabilityId) {
      case 'dosage':
        final argumentErrors = DosageToolService.validateArguments(arguments);
        return argumentErrors.isEmpty
            ? const []
            : List.unmodifiable(argumentErrors.map(
                (error) => 'ACTION_PROPOSAL_DOSAGE_ARGUMENT_INVALID:$error',
              ));
      case 'solar_terms':
        if (arguments.keys.any((key) => key != 'term')) {
          return const ['ACTION_PROPOSAL_SOLAR_TERM_ARGUMENT_UNDECLARED'];
        }
        final term = arguments['term'];
        if (term != null &&
            (term.trim().isEmpty || term != term.trim() ||
                !SolarTermToolService.termNames.contains(term))) {
          return const ['ACTION_PROPOSAL_SOLAR_TERM_NOT_IN_APP_ALLOWLIST'];
        }
        return const [];
      case 'yuxiaji_omen':
        return arguments.isEmpty
            ? const []
            : const ['ACTION_PROPOSAL_YUXIAJI_DOES_NOT_ACCEPT_MODEL_ARGUMENTS'];
      case 'sanshan_lingqian':
        return arguments.isEmpty
            ? const []
            : const ['ACTION_PROPOSAL_SANSHAN_SIGN_IS_APP_GENERATED'];
      default:
        return const ['ACTION_PROPOSAL_CAPABILITY_NOT_PLAN_ELIGIBLE'];
    }
  }

  static bool _isValidRequestId(String value) =>
      RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value);

  static bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  static ReasoningActionProposalGateResult _rejected(List<String> errors) =>
      ReasoningActionProposalGateResult._(
        status: ReasoningActionProposalGateStatus.rejected,
        errors: errors,
      );
}

enum ReasoningActionProposalGateStatus {
  rejected,
  confirmationRequired,
  declined,
  authorized,
}

/// Immutable information shown by the App-owned confirmation UI.
class ReasoningActionProposalPreview {
  ReasoningActionProposalPreview._({
    required this.requestId,
    required this.proposalId,
    required this.capabilityId,
    required this.toolId,
    required Map<String, String> arguments,
    required Set<String> requestCapabilityAllowlist,
  })  : arguments = Map<String, String>.unmodifiable(arguments),
        requestCapabilityAllowlist =
            Set<String>.unmodifiable(requestCapabilityAllowlist);

  final String requestId;
  final String proposalId;
  final String capabilityId;
  final String toolId;
  final Map<String, String> arguments;
  final Set<String> requestCapabilityAllowlist;
}

/// Only an authorized result has a plan. This type never runs an executor.
class ReasoningActionProposalGateResult {
  ReasoningActionProposalGateResult._({
    required this.status,
    this.preview,
    this.plan,
    required List<String> errors,
  }) : errors = List<String>.unmodifiable(errors);

  final ReasoningActionProposalGateStatus status;
  final ReasoningActionProposalPreview? preview;
  final ToolExecutionPlan? plan;
  final List<String> errors;

  bool get requiresConfirmation =>
      status == ReasoningActionProposalGateStatus.confirmationRequired;

  bool get isAuthorized =>
      status == ReasoningActionProposalGateStatus.authorized && plan != null;
}
