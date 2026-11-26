import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/reasoning_request.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/services/reasoning_request_prompt_formatter.dart';

SessionStateSnapshot snapshot({
  int sessionId = 7,
  SessionStateStatus status = SessionStateStatus.restored,
}) =>
    SessionStateSnapshot(
      sessionId: sessionId,
      revision: 'rev-3',
      status: status,
      facts: [
        SessionStateFact(
          factId: 'fact-1',
          key: '主诉',
          value: {'text': '用户原话', 'tags': ['头痛', '怕冷']},
          provenance: SessionFactProvenance.userConfirmed,
          sourceIds: const ['local-session:fact-1'],
        ),
        SessionStateFact(
          factId: 'fact-2',
          key: '推断',
          value: '待确认',
          provenance: SessionFactProvenance.modelInferred,
        ),
      ],
      evidenceReferences: const [
        SessionEvidenceReference(
          sourceId: 'source:existing',
          sourceVersion: 'UNKNOWN',
          evidenceId: 'evidence-old',
        ),
      ],
      activeTaskId: 'task-1',
    );

ReasoningExecutionResult successResult() => ReasoningExecutionResult(
      invocationId: 'invoke-1',
      capabilityId: 'dosage',
      status: ReasoningExecutionStatus.succeeded,
      actualArguments: const {'formulaId': 'formula-1'},
      resultValues: const {'result': 'App 计算结果'},
      sourceIds: const ['formula-engine:v1'],
    );

ReasoningRequest request({
  List<ReasoningEvidenceReference> ranked = const [
    ReasoningEvidenceReference(
      evidenceId: 'evidence-1',
      sourceId: 'source:one',
    ),
  ],
  List<String> known = const ['evidence-1', 'evidence-dropped'],
  List<ReasoningExecutionResult> results = const [],
  SessionStateSnapshot? session,
}) =>
    ReasoningRequest(
      requestId: 'request-123',
      sessionId: 7,
      userText: '  用户原始问题：请解释这段原文。\n不要改写  ',
      mode: 'learning',
      responseSchemaVersion: 1,
      sessionState: session ?? snapshot(),
      rankedEvidence: ranked,
      knownEvidenceIds: known,
      executionResults: results,
    );

void main() {
  group('ReasoningRequest', () {
    test('preserves the exact user text and freezes its collections', () {
      final value = request(results: [successResult()]);

      expect(
        value.userText,
        '  用户原始问题：请解释这段原文。\n不要改写  ',
      );
      expect(value.sessionId, 7);
      expect(value.rankedEvidenceIds, ['evidence-1']);
      expect(value.knownEvidenceIds, ['evidence-1', 'evidence-dropped']);
      expect(
        () => value.rankedEvidence.add(
          const ReasoningEvidenceReference(
            evidenceId: 'another',
            sourceId: 'source:another',
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => value.knownEvidenceIds.add('another'),
        throwsUnsupportedError,
      );
      expect(
        () => value.executionResults.add(successResult()),
        throwsUnsupportedError,
      );
      expect(
        () => value.rankedEvidence[0] = const ReasoningEvidenceReference(
          evidenceId: 'replace',
          sourceId: 'source:replace',
        ),
        throwsUnsupportedError,
      );
    });

    test('toMap recursively freezes DTO, evidence, session and execution projections', () {
      final value = request(results: [successResult()]);
      final projection = value.toMap();

      expect(() => projection['mode'] = 'changed', throwsUnsupportedError);
      final ranked = projection['rankedEvidence'] as List;
      expect(() => ranked.add(const {}), throwsUnsupportedError);
      expect(
        () => (ranked.single as Map)['sourceId'] = 'changed',
        throwsUnsupportedError,
      );

      final execution = projection['executionResults'] as List;
      expect(() => execution.clear(), throwsUnsupportedError);
      expect(
        () => (execution.single as Map)['capabilityId'] = 'changed',
        throwsUnsupportedError,
      );
      final actualArguments =
          (execution.single as Map)['actualArguments'] as Map;
      expect(
        () => actualArguments['formulaId'] = 'changed',
        throwsUnsupportedError,
      );

      final session = projection['sessionState'] as Map;
      expect(() => session['status'] = 'UNKNOWN', throwsUnsupportedError);
      final facts = session['facts'] as List;
      expect(() => facts.clear(), throwsUnsupportedError);
      expect(() => (facts.first as Map)['key'] = 'changed',
          throwsUnsupportedError);
      final nestedValue = (facts.first as Map)['value'] as Map;
      expect(() => nestedValue['text'] = 'changed', throwsUnsupportedError);
      final evidenceReferences = session['evidenceReferences'] as List;
      expect(() => evidenceReferences.clear(), throwsUnsupportedError);
      expect(
        () => (evidenceReferences.first as Map)['sourceId'] = 'changed',
        throwsUnsupportedError,
      );
    });

    test('accepts valid zero-argument deterministic execution results', () {
      final noArgumentResult = ReasoningExecutionResult(
        invocationId: 'invoke-yuxiaji',
        capabilityId: 'yuxiaji_omen',
        status: ReasoningExecutionStatus.succeeded,
        resultValues: const {
          '当前时辰': '午时',
          '数据范围': '本地时辰条目',
        },
        sourceIds: const ['local-data:yuxiaji-omen'],
      );
      final value = request(results: [noArgumentResult]);

      expect(
        value.executionResults.single.status,
        ReasoningExecutionStatus.succeeded,
      );
      expect(value.executionResults.single.actualArguments, isEmpty);
      expect(value.executionResults.single.resultValues, isNotEmpty);
      expect(
        value.executionResults.single.sourceIds,
        ['local-data:yuxiaji-omen'],
      );
    });

    test('rejects invalid request identity, session scope and schema version', () {
      expect(
        () => ReasoningRequest(
          requestId: ' ',
          sessionId: 7,
          userText: '问题',
          mode: 'learning',
          responseSchemaVersion: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => request(session: snapshot(sessionId: 8)),
        throwsArgumentError,
      );
      expect(
        () => ReasoningRequest(
          requestId: 'request-1',
          sessionId: 0,
          userText: '问题',
          mode: 'learning',
          responseSchemaVersion: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningRequest(
          requestId: 'request-1',
          sessionId: 7,
          userText: '问题',
          mode: 'learning',
          responseSchemaVersion: 2,
        ),
        throwsArgumentError,
      );
    });

    test('requires ranked IDs to be unique members of known candidates', () {
      expect(
        () => request(
          ranked: const [
            ReasoningEvidenceReference(
              evidenceId: 'missing',
              sourceId: 'source:missing',
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => request(
          ranked: const [
            ReasoningEvidenceReference(
              evidenceId: 'evidence-1',
              sourceId: 'source:one',
            ),
            ReasoningEvidenceReference(
              evidenceId: 'evidence-1',
              sourceId: 'source:duplicate',
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => request(known: const ['evidence-1', 'evidence-1']),
        throwsArgumentError,
      );
    });

    test('does not expose facts from UNKNOWN or mismatched session snapshots', () {
      final unknown = request(
        session: snapshot(status: SessionStateStatus.unknown),
      );
      final unknownMap = unknown.toMap()['sessionState'] as Map;
      expect(unknownMap['facts'], isEmpty);
      expect(unknownMap['evidenceReferences'], isEmpty);
      expect(unknownMap.containsKey('activeTaskId'), isFalse);

      final mismatched = request(
        session: snapshot(status: SessionStateStatus.sessionMismatch),
      );
      final mismatchedMap = mismatched.toMap()['sessionState'] as Map;
      expect(mismatchedMap['facts'], isEmpty);
      expect(mismatchedMap['evidenceReferences'], isEmpty);
      expect(mismatchedMap.containsKey('activeTaskId'), isFalse);
    });

    test('keeps UNKNOWN execution state and rejects unsubstantiated success', () {
      final unknown = ReasoningExecutionResult(
        invocationId: 'invoke-unknown',
        capabilityId: 'dosage',
        status: ReasoningExecutionStatus.unknown,
        actualArguments: const {'formulaId': 'formula-1'},
        failureCode: 'EXECUTION_RESULT_LOST',
      );
      final value = request(results: [unknown, successResult()]);
      expect(value.executionResults.first.status, ReasoningExecutionStatus.unknown);
      expect(
        value.executionResults.first.toMap()['status'],
        'UNKNOWN',
      );

      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.succeeded,
          actualArguments: const {'formulaId': 'formula-1'},
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.notStarted,
          resultValues: const {'result': '伪结果'},
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.unknown,
          resultValues: const {'result': '未验证结果'},
          failureCode: 'EXECUTION_RESULT_LOST',
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.failed,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.failed,
          failureCode: '   ',
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.unknown,
          failureCode: ' EXECUTION_RESULT_LOST ',
        ),
        throwsArgumentError,
      );
      expect(
        () => ReasoningExecutionResult(
          invocationId: 'invoke-invalid',
          capabilityId: 'dosage',
          status: ReasoningExecutionStatus.notStarted,
          actualArguments: const {'formulaId': 'formula-1'},
        ),
        throwsArgumentError,
      );
      expect(
        () => request(results: [successResult(), successResult()]),
        throwsArgumentError,
      );
    });

    test('deep-freezes App result maps and nested session facts', () {
      final appResult = successResult();
      expect(
        () => appResult.actualArguments['formulaId'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => appResult.resultValues['result'] = 'changed',
        throwsUnsupportedError,
      );
      final value = request();
      final factValue = value.sessionState!.facts.first.value as Map;
      expect(
        () => factValue['text'] = 'changed',
        throwsUnsupportedError,
      );
      final nestedTags = factValue['tags'] as List;
      expect(
        () => nestedTags.add('new'),
        throwsUnsupportedError,
      );
    });
  });

  group('ReasoningRequestPromptFormatter', () {
    test('keeps original text separate and formats bounded request metadata', () {
      final value = request(
        results: [
          successResult(),
          ReasoningExecutionResult(
            invocationId: 'invoke-unknown',
            capabilityId: 'almanac',
            status: ReasoningExecutionStatus.unknown,
            failureCode: 'NATIVE_RESULT_UNKNOWN',
          ),
        ],
      );
      final formatted =
          ReasoningRequestPromptFormatter.formatSupplementalContext(value);

      expect(formatted, startsWith(ReasoningRequestPromptFormatter.header));
      final envelope = jsonDecode(
        formatted.substring(ReasoningRequestPromptFormatter.header.length + 1),
      ) as Map<String, dynamic>;

      expect(envelope['requestId'], 'request-123');
      expect(envelope['sessionId'], 7);
      expect(envelope['mode'], 'learning');
      expect(envelope['responseSchemaVersion'], 1);
      expect(envelope.containsKey('userText'), isFalse);
      expect(formatted, isNot(contains('用户原始问题：')));
      final sessionMetadata =
          envelope['sessionStateMetadata'] as Map<String, dynamic>;
      expect(sessionMetadata['sessionId'], 7);
      expect(sessionMetadata['revision'], 'rev-3');
      expect(sessionMetadata['status'], 'RESTORED');
      expect(
        sessionMetadata['contentTransport'],
        'NATIVE_SESSION_STATE_CONTEXT',
      );
      // Facts/source references are already passed via the Native-owned
      // session_state_context field and must not be duplicated here.
      expect(formatted, isNot(contains('用户原话')));
      expect(formatted, isNot(contains('待确认')));
      expect(formatted, isNot(contains('source:existing')));
      expect(envelope['rankedEvidence'], [
        {'evidenceId': 'evidence-1'},
      ]);
      expect(formatted, isNot(contains('source:one')),
          reason: 'sourceId is an App-owned lookup pointer and is not exposed to the model');
      expect(envelope['knownEvidenceIds'], [
        'evidence-1',
        'evidence-dropped',
      ]);
      final results = envelope['executionResults'] as List;
      expect((results[0] as Map)['status'], 'SUCCEEDED');
      expect((results[1] as Map)['status'], 'UNKNOWN');
      expect(formatted, contains('not allowed citations'));
      expect(formatted, contains('does not grant permission'));
    });

    test('rejects supplemental metadata that exceeds its explicit character bound', () {
      final largeResult = ReasoningExecutionResult(
        invocationId: 'invoke-large',
        capabilityId: 'dosage',
        status: ReasoningExecutionStatus.succeeded,
        actualArguments: const {'formulaId': 'formula-1'},
        resultValues: {'result': 'x' * 25000},
        sourceIds: const ['formula-engine:v1'],
      );
      final largeRequest = request(results: [largeResult]);
      expect(
        () => ReasoningRequestPromptFormatter.formatSupplementalContext(largeRequest),
        throwsStateError,
      );
    });

    test('includes strict response schema and action/evidence boundaries', () {
      final formatted = ReasoningRequestPromptFormatter.formatSupplementalContext(request());
      final envelope = jsonDecode(
        formatted.substring(ReasoningRequestPromptFormatter.header.length + 1),
      ) as Map<String, dynamic>;
      final contract = envelope['responseContract'] as Map<String, dynamic>;
      expect(contract['schemaVersion'], 1);
      expect(contract['requiredFields'], contains('referencedEvidenceIds'));
      expect(contract['responseKinds'], contains('ACTION_PROPOSAL'));
      expect(contract['modelStatuses'], ['COMPLETED', 'INSUFFICIENT_EVIDENCE']);
      expect(contract['rules'], contains('ACTION_PROPOSAL is an untrusted proposal; it is not authorization or execution.'));
    });

    test('marks resolved detail-page context as sufficient grounding without ranked RAG evidence', () {
      final value = request(ranked: const [], known: const []);
      final formatted = ReasoningRequestPromptFormatter.formatSupplementalContext(
        value,
        primaryContextAvailable: true,
      );
      final envelope = jsonDecode(
        formatted.substring(ReasoningRequestPromptFormatter.header.length + 1),
      ) as Map<String, dynamic>;
      expect(envelope['primaryContext'], {
        'available': true,
        'transport': 'SEPARATE_MODEL_CONTEXT_FIELD',
      });
      final contract = envelope['responseContract'] as Map<String, dynamic>;
      final rules = (contract['rules'] as List).cast<String>();
      final boundaries = (envelope['boundaries'] as List).cast<String>();
      expect(
        rules.any((item) => item.contains('valid grounding source even when rankedEvidence is empty')),
        isTrue,
      );
      expect(
        boundaries.any((item) => item.contains('not a rankedEvidence item')),
        isTrue,
      );
    });
    test('marks absent session state as UNKNOWN without inventing facts', () {
      final value = ReasoningRequest(
        requestId: 'request-no-memory',
        sessionId: 7,
        userText: '用户原话',
        mode: 'automatic',
        responseSchemaVersion: 1,
      );
      final formatted =
          ReasoningRequestPromptFormatter.formatSupplementalContext(value);
      final envelope = jsonDecode(
        formatted.substring(ReasoningRequestPromptFormatter.header.length + 1),
      ) as Map<String, dynamic>;
      final metadata = envelope['sessionStateMetadata'] as Map<String, dynamic>;
      expect(metadata['status'], 'UNKNOWN');
      expect(metadata['revision'], 'UNKNOWN');
      expect(metadata['contentTransport'], 'NATIVE_SESSION_STATE_CONTEXT');
      expect(formatted, isNot(contains('结构化事实：未提供')));
    });
  });
}
