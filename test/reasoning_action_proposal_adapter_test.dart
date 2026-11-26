import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/models/tool_execution_plan.dart';
import 'package:nihaisha_app/services/assistant_knowledge_context.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_adapter.dart';
import 'package:nihaisha_app/services/reasoning_action_proposal_gate.dart';

SessionStateSnapshot _session() => SessionStateSnapshot(
      sessionId: 7,
      revision: 'rev-1',
      status: SessionStateStatus.restored,
      facts: const [],
      evidenceReferences: const [],
    );

AssistantKnowledgeContextResult _knowledge() =>
    const AssistantKnowledgeContextResult(text: '');

ReasoningRequest _request({
  Set<String> capabilities = const {'dosage'},
}) =>
    ReasoningActionProposalAdapter.createRequest(
      requestId: '0123456789abcdef0123456789abcdef',
      sessionId: 7,
      userText: '请换算这项方剂剂量',
      sessionState: _session(),
      knowledge: _knowledge(),
      requestCapabilityAllowlist: capabilities,
    );

String _proposalPayload({
  String requestId = '0123456789abcdef0123456789abcdef',
  String capabilityId = 'dosage',
}) =>
    jsonEncode({
      'schemaVersion': 1,
      'requestId': requestId,
      'responseKind': 'ACTION_PROPOSAL',
      'status': 'COMPLETED',
      'segments': ['建议调用 App 内置剂量换算工具。'],
      'referencedEvidenceIds': <String>[],
      'unknowns': <String>[],
      'conflicts': <String>[],
      'omittedEvidenceIds': <String>[],
      'actionProposal': {
        'proposalId': 'proposal-001',
        'capabilityId': capabilityId,
        'arguments': {
          'value': '3',
          'unit': '两',
          'standard': 'han',
        },
      },
    });

void main() {
  group('ReasoningActionProposalAdapter', () {
    test('creates a tool-mode request with an immutable request-scoped allowlist', () {
      final request = _request(
        capabilities: const {'dosage', 'solar_terms'},
      );

      expect(request.mode, 'tools');
      expect(request.allowedCapabilityIds, ['dosage', 'solar_terms']);
      expect(request.toMap()['allowedCapabilityIds'], ['dosage', 'solar_terms']);
      expect(
        () => request.allowedCapabilityIds.add('yuxiaji_omen'),
        throwsUnsupportedError,
      );
    });

    test('decodes an allowed proposal into a preview, never an executable plan', () {
      final request = _request();
      final result = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: _proposalPayload(),
        request: request,
        knowledge: _knowledge(),
      );

      expect(result.decodeResult.isUsable, isFalse);
      expect(result.decodeResult.response, isNull);
      expect(result.decodeResult.diagnostics,
          contains('ACTION_PROPOSAL_AWAITING_APP_CONFIRMATION'));
      expect(result.requiresConfirmation, isTrue);
      expect(result.gateResult?.preview, isNotNull);
      expect(result.gateResult?.plan, isNull);
      expect(result.answerResult, isNull);
    });

    test('only explicit confirmation returns a single-step App plan', () {
      final request = _request();
      final prepared = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: _proposalPayload(),
        request: request,
        knowledge: _knowledge(),
      );
      final preview = prepared.gateResult!.preview!;

      final declined =
          ReasoningActionProposalAdapter.authorizeAfterConfirmation(
        preview: preview,
        request: request,
        confirmedByUser: false,
      );
      expect(declined.status, ReasoningActionProposalGateStatus.declined);
      expect(declined.plan, isNull);

      final confirmed =
          ReasoningActionProposalAdapter.authorizeAfterConfirmation(
        preview: preview,
        request: request,
        confirmedByUser: true,
      );
      expect(confirmed.isAuthorized, isTrue);
      expect(confirmed.plan!.origin, InvocationOrigin.aiDispatch);
      expect(confirmed.plan!.steps, hasLength(1));
      expect(confirmed.plan!.steps.single.toolId, 'dosage');
    });

    test('rejects a model proposal outside the current request allowlist', () {
      final request = _request(capabilities: const {'solar_terms'});
      final result = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: _proposalPayload(capabilityId: 'dosage'),
        request: request,
        knowledge: _knowledge(),
      );

      expect(result.isRejected, isTrue);
      expect(result.requiresConfirmation, isFalse);
      expect(result.decodeResult.isUsable, isFalse);
      expect(
        result.decodeResult.diagnostics,
        contains('REASONING_RESPONSE_CAPABILITY_NOT_REGISTERED'),
      );
    });

    test('rejects action proposals that carry evidence references the preview would hide', () {
      final request = _request();
      final payload = jsonDecode(_proposalPayload()) as Map<String, dynamic>;
      payload['referencedEvidenceIds'] = ['evidence-1'];
      final result = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: jsonEncode(payload),
        request: request,
        knowledge: _knowledge(),
      );

      expect(result.isRejected, isTrue);
      expect(
        result.decodeResult.diagnostics,
        contains('REASONING_ACTION_PROPOSAL_MUST_NOT_DROP_EVIDENCE_REFERENCES'),
      );
    });

    test('refuses unsupported capability IDs before they enter a model request', () {
      expect(
        () => _request(capabilities: const {'guji_library'}),
        throwsArgumentError,
      );
    });

    test('rejects action decoding without a tool-mode request scope', () {
      final request = ReasoningRequest(
        requestId: '0123456789abcdef0123456789abcdef',
        sessionId: 7,
        userText: '请解释方剂',
        mode: 'tools',
        responseSchemaVersion: 1,
      );
      final result = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: _proposalPayload(),
        request: request,
        knowledge: _knowledge(),
      );

      expect(result.isRejected, isTrue);
      expect(
        result.decodeResult.diagnostics,
        contains('REASONING_TOOL_REQUEST_CAPABILITY_SCOPE_MISSING'),
      );
    });

    test('revalidates the exact request allowlist after the confirmation surface returns', () {
      final originalRequest = _request();
      final prepared = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: _proposalPayload(),
        request: originalRequest,
        knowledge: _knowledge(),
      );
      final widenedRequest = _request(
        capabilities: const {'dosage', 'solar_terms'},
      );

      final result =
          ReasoningActionProposalAdapter.authorizeAfterConfirmation(
        preview: prepared.gateResult!.preview!,
        request: widenedRequest,
        confirmedByUser: true,
      );

      expect(result.isAuthorized, isFalse);
      expect(result.plan, isNull);
      expect(
        result.errors,
        contains('ACTION_PROPOSAL_REQUEST_ALLOWLIST_CHANGED'),
      );
    });

    test('rejects a preview from another request even when its capability is allowed', () {
      final request = _request();
      final prepared = ReasoningActionProposalAdapter.decodeAndPrepare(
        raw: _proposalPayload(),
        request: request,
        knowledge: _knowledge(),
      );
      final otherRequest = ReasoningActionProposalAdapter.createRequest(
        requestId: 'fedcba9876543210fedcba9876543210',
        sessionId: 7,
        userText: '另一轮用户请求',
        sessionState: _session(),
        knowledge: _knowledge(),
        requestCapabilityAllowlist: const {'dosage'},
      );

      final result =
          ReasoningActionProposalAdapter.authorizeAfterConfirmation(
        preview: prepared.gateResult!.preview!,
        request: otherRequest,
        confirmedByUser: true,
      );

      expect(result.isAuthorized, isFalse);
      expect(result.plan, isNull);
      expect(result.errors, contains('ACTION_PROPOSAL_REQUEST_ID_MISMATCH'));
    });

    test('does not manufacture a request when no App capability was selected', () {
      expect(
        () => ReasoningActionProposalAdapter.createRequest(
          requestId: '0123456789abcdef0123456789abcdef',
          sessionId: 7,
          userText: '请计算',
          sessionState: _session(),
          knowledge: _knowledge(),
          requestCapabilityAllowlist: const {},
        ),
        throwsArgumentError,
      );
    });
  });
}
