import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/reasoning_response.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/assistant_tool_execution_plan_builder.dart';
import 'package:nihaisha_app/services/headless_tool_dispatcher.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_gate.dart';
import 'package:nihaisha_app/services/solar_term_tool_service.dart';

ReasoningResponse _response({
  String requestId = '0123456789abcdef0123456789abcdef',
  String proposalId = 'proposal-001',
  String capabilityId = 'dosage',
  Map<String, String> arguments = const {
    'value': '3',
    'unit': '两',
    'standard': 'han',
  },
  ReasoningResponseKind responseKind = ReasoningResponseKind.actionProposal,
  ReasoningResponseStatus status = ReasoningResponseStatus.completed,
  bool includeProposal = true,
}) =>
    ReasoningResponse(
      requestId: requestId,
      responseKind: responseKind,
      status: status,
      segments: const ['App 可执行动作候选'],
      referencedEvidenceIds: const [],
      unknowns: const [],
      conflicts: const [],
      omittedEvidenceIds: const [],
      actionProposal: includeProposal
          ? BusinessActionProposal(
              proposalId: proposalId,
              capabilityId: capabilityId,
              arguments: arguments,
            )
          : null,
    );

void main() {
  group('ReasoningActionProposalGate', () {
    const requestId = '0123456789abcdef0123456789abcdef';

    test('uses exactly the existing four plan-eligible Headless capabilities', () {
      expect(
        ReasoningActionProposalGate.supportedCapabilityIds,
        {
          'dosage',
          'solar_terms',
          'yuxiaji_omen',
          'sanshan_lingqian',
        },
      );
      for (final capabilityId
          in ReasoningActionProposalGate.supportedCapabilityIds) {
        final tool = AssistantToolRouter.byId(capabilityId);
        expect(tool, isNotNull, reason: capabilityId);
        expect(tool!.capabilityId, capabilityId);
        expect(HeadlessToolDispatcher.hasExecutor(tool.id), isTrue);
        expect(HeadlessToolDispatcher.capabilityIdForTool(tool.id), capabilityId);
        expect(AssistantToolExecutionPlanBuilder.supportsPlan(tool.id), isTrue);
      }
      expect(SolarTermToolService.termNames.toSet(),
          AssistantToolRouter.solarTermNames.toSet());
    });

    test('prepares a confirmation preview but exposes no plan before consent', () {
      final result = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );

      expect(result.status,
          ReasoningActionProposalGateStatus.confirmationRequired);
      expect(result.requiresConfirmation, isTrue);
      expect(result.preview, isNotNull);
      expect(result.preview!.arguments, {
        'value': '3',
        'unit': '两',
        'standard': 'han',
      });
      expect(result.plan, isNull);
      expect(() => result.preview!.arguments['unit'] = '升',
          throwsUnsupportedError);
    });

    test('returns an AI-origin single-step plan only after explicit confirmation', () {
      final prepared = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );
      final authorized =
          ReasoningActionProposalGate.authorizeAfterConfirmation(
        preview: prepared.preview!,
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
        confirmedByUser: true,
      );

      expect(authorized.isAuthorized, isTrue);
      expect(authorized.plan, isNotNull);
      expect(authorized.plan!.origin, InvocationOrigin.aiDispatch);
      expect(authorized.plan!.steps, hasLength(1));
      expect(authorized.plan!.steps.single.toolId, 'dosage');
      expect(authorized.plan!.steps.single.capabilityId, 'dosage');
      expect(authorized.plan!.steps.single.arguments, prepared.preview!.arguments);
    });

    test('declining confirmation returns no executable plan', () {
      final prepared = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );
      final declined =
          ReasoningActionProposalGate.authorizeAfterConfirmation(
        preview: prepared.preview!,
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
        confirmedByUser: false,
      );

      expect(declined.status, ReasoningActionProposalGateStatus.declined);
      expect(declined.plan, isNull);
      expect(declined.errors, contains('ACTION_PROPOSAL_USER_CONSENT_NOT_GRANTED'));
    });

    test('rejects request IDs outside Native 32-hex request contract', () {
      final result = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(requestId: 'request-1'),
        expectedRequestId: 'request-1',
        requestCapabilityAllowlist: const {'dosage'},
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.errors, contains('ACTION_PROPOSAL_REQUEST_ID_MISMATCH'));
    });

    test('rejects malformed proposal identifiers before creating a preview', () {
      final result = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(proposalId: '../delete'),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.preview, isNull);
      expect(result.errors, contains('ACTION_PROPOSAL_ID_INVALID'));
    });

    test('rejects a proposal bound to another request ID', () {
      final result = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(requestId: 'fedcba9876543210fedcba9876543210'),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.errors, contains('ACTION_PROPOSAL_REQUEST_ID_MISMATCH'));
    });

    test('rejects non-proposal responses and missing proposal bodies', () {
      for (final response in [
        _response(responseKind: ReasoningResponseKind.answer),
        _response(includeProposal: false),
        _response(status: ReasoningResponseStatus.insufficientEvidence),
      ]) {
        final result = ReasoningActionProposalGate.prepareForConfirmation(
          response: response,
          expectedRequestId: requestId,
          requestCapabilityAllowlist: const {'dosage'},
        );
        expect(result.status, ReasoningActionProposalGateStatus.rejected);
        expect(result.plan, isNull);
      }
    });

    test('rejects capabilities that are not in the current request allowlist', () {
      final result = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'solar_terms'},
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.errors,
          contains('ACTION_PROPOSAL_CAPABILITY_NOT_ALLOWED_FOR_REQUEST'));
    });

    test('rejects Page-only capabilities even when they are in the request allowlist', () {
      final result = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(
          capabilityId: 'guji_library',
          arguments: const {},
        ),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'guji_library'},
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.errors,
          contains('ACTION_PROPOSAL_CAPABILITY_NOT_PLAN_ELIGIBLE'));
    });

    test('enforces the existing dosage conversion argument schema', () {
      final invalid = [
        const {'value': '0', 'unit': '两', 'standard': 'han'},
        const {'value': '3', 'unit': '两'},
        const {'value': '3', 'unit': '升', 'standard': 'invalid'},
        const {'value': '3', 'unit': '两', 'standard': 'han', 'extra': 'x'},
      ];
      for (final arguments in invalid) {
        final result = ReasoningActionProposalGate.prepareForConfirmation(
          response: _response(arguments: arguments),
          expectedRequestId: requestId,
          requestCapabilityAllowlist: const {'dosage'},
        );
        expect(result.status, ReasoningActionProposalGateStatus.rejected,
            reason: arguments.toString());
      }
    });

    test('validates the solar-term choice and rejects undeclared arguments', () {
      final allowed = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(
          capabilityId: 'solar_terms',
          arguments: const {'term': '立春'},
        ),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'solar_terms'},
      );
      expect(allowed.requiresConfirmation, isTrue);

      final currentTerm = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(
          capabilityId: 'solar_terms',
          arguments: const {},
        ),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'solar_terms'},
      );
      expect(currentTerm.requiresConfirmation, isTrue);

      final invalid = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(
          capabilityId: 'solar_terms',
          arguments: const {'term': '不存在的节气'},
        ),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'solar_terms'},
      );
      expect(invalid.status, ReasoningActionProposalGateStatus.rejected);
    });

    test('does not let the model choose local time or sign index', () {
      for (final capabilityId in ['yuxiaji_omen', 'sanshan_lingqian']) {
        final accepted = ReasoningActionProposalGate.prepareForConfirmation(
          response: _response(
            capabilityId: capabilityId,
            arguments: const {},
          ),
          expectedRequestId: requestId,
          requestCapabilityAllowlist: {capabilityId},
        );
        expect(accepted.requiresConfirmation, isTrue, reason: capabilityId);

        final rejected = ReasoningActionProposalGate.prepareForConfirmation(
          response: _response(
            capabilityId: capabilityId,
            arguments: const {'hour': '午时'},
          ),
          expectedRequestId: requestId,
          requestCapabilityAllowlist: {capabilityId},
        );
        expect(rejected.status, ReasoningActionProposalGateStatus.rejected);
      }
    });

    test('rejects a request allowlist that changed while confirmation was open', () {
      final prepared = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );
      final result = ReasoningActionProposalGate.authorizeAfterConfirmation(
        preview: prepared.preview!,
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'solar_terms'},
        confirmedByUser: true,
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.plan, isNull);
      expect(result.errors,
          contains('ACTION_PROPOSAL_REQUEST_ALLOWLIST_CHANGED'));
    });

    test('revalidates the request binding at the final consent boundary', () {
      final prepared = ReasoningActionProposalGate.prepareForConfirmation(
        response: _response(),
        expectedRequestId: requestId,
        requestCapabilityAllowlist: const {'dosage'},
      );
      final result = ReasoningActionProposalGate.authorizeAfterConfirmation(
        preview: prepared.preview!,
        expectedRequestId: 'fedcba9876543210fedcba9876543210',
        requestCapabilityAllowlist: const {'dosage'},
        confirmedByUser: true,
      );

      expect(result.status, ReasoningActionProposalGateStatus.rejected);
      expect(result.plan, isNull);
    });
  });
}
