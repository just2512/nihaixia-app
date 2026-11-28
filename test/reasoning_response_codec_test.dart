import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/reasoning_response.dart';
import 'package:nihaisha_app/services/reasoning_response_codec.dart';

void main() {
  const requestId = 'request-1';
  const rankedEvidence = {'evidence-1', 'evidence-2'};
  const knownEvidence = {'evidence-1', 'evidence-2', 'evidence-3'};

  Map<String, Object?> answerPayload({
    String responseKind = 'ANSWER',
    String status = 'COMPLETED',
    String responseRequestId = requestId,
    List<Object?> referenced = const ['evidence-1'],
    List<Object?> omitted = const [],
  }) => {
        'schemaVersion': 1,
        'requestId': responseRequestId,
        'responseKind': responseKind,
        'status': status,
        'segments': ['基于本轮已提供的证据作解释。'],
        'referencedEvidenceIds': referenced,
        'unknowns': <String>[],
        'conflicts': <String>[],
        'omittedEvidenceIds': omitted,
      };

  ReasoningResponseDecodeResult decode(
    Object payload, {
    Set<String> allowedCapabilities = const {},
    String? expectedAttachmentType,
  }) =>
      ReasoningResponseCodec.decode(
        raw: payload is String ? payload : jsonEncode(payload),
        expectedRequestId: requestId,
        rankedEvidenceIds: rankedEvidence,
        knownEvidenceIds: knownEvidence,
        allowedCapabilityIds: allowedCapabilities,
        expectedAttachmentType: expectedAttachmentType,
      );

  test('accepts a completed answer and freezes response collections', () {
    final result = decode(answerPayload());

    expect(result.status, ReasoningResponseStatus.completed);
    expect(result.isUsable, isTrue);
    expect(result.response?.responseKind, ReasoningResponseKind.answer);
    expect(result.response?.referencedEvidenceIds, ['evidence-1']);
    expect(
      result.diagnostics,
      contains('REASONING_RESPONSE_V1_VALIDATED'),
    );
  });

  test('accepts an explicit insufficient-evidence response', () {
    final result = decode(
      answerPayload(
        responseKind: 'INSUFFICIENT_EVIDENCE',
        status: 'INSUFFICIENT_EVIDENCE',
        referenced: const [],
      ),
    );

    expect(result.status, ReasoningResponseStatus.insufficientEvidence);
    expect(result.isUsable, isTrue);
    expect(
      result.response?.responseKind,
      ReasoningResponseKind.insufficientEvidence,
    );
  });

  test('accepts image observations only for image attachment requests', () {
    final payload = answerPayload()
      ..['attachmentResult'] = {
        'type': 'image',
        'observations': ['舌体偏淡红', '舌苔分布可见'],
      };
    final accepted = decode(payload, expectedAttachmentType: 'image');
    final mismatch = decode(payload, expectedAttachmentType: 'audio');
    final unexpected = decode(payload);

    expect(accepted.isUsable, isTrue);
    expect(accepted.response?.attachmentResult?.observations, ['舌体偏淡红', '舌苔分布可见']);
    expect(mismatch.status, ReasoningResponseStatus.parseFailed);
    expect(unexpected.status, ReasoningResponseStatus.parseFailed);
  });

  test('accepts audio transcript as unconfirmed structured draft', () {
    final payload = answerPayload()
      ..['attachmentResult'] = {
        'type': 'audio',
        'transcriptDraft': '最近两天睡眠不太好。',
      };
    final accepted = decode(payload, expectedAttachmentType: 'audio');
    final missing = decode(answerPayload(), expectedAttachmentType: 'audio');
    final wrongShape = answerPayload()
      ..['attachmentResult'] = {
        'type': 'audio',
        'observations': ['不应接受'],
      };

    expect(accepted.isUsable, isTrue);
    expect(accepted.response?.attachmentResult?.transcriptDraft, '最近两天睡眠不太好。');
    expect(missing.status, ReasoningResponseStatus.parseFailed);
    expect(decode(wrongShape, expectedAttachmentType: 'audio').status, ReasoningResponseStatus.parseFailed);
  });

  test('returns EMPTY for an empty model reply', () {
    final result = decode('   ');
    expect(result.status, ReasoningResponseStatus.empty);
    expect(result.response, isNull);
    expect(result.isUsable, isFalse);
  });

  test('rejects malformed JSON and non-object roots as PARSE_FAILED', () {
    expect(
      decode('{not-json').status,
      ReasoningResponseStatus.parseFailed,
    );
    expect(
      decode(['not', 'an', 'object']).status,
      ReasoningResponseStatus.parseFailed,
    );
  });

  test('rejects missing, unknown, and unsupported schema fields', () {
    final missing = answerPayload()..remove('segments');
    final unknown = answerPayload()..['authorized'] = true;
    final unsupported = answerPayload()..['schemaVersion'] = 2;
    final floatingPointVersion = answerPayload()..['schemaVersion'] = 1.0;

    expect(decode(missing).status, ReasoningResponseStatus.parseFailed);
    expect(decode(unknown).status, ReasoningResponseStatus.parseFailed);
    expect(decode(unsupported).status, ReasoningResponseStatus.parseFailed);
    expect(
      decode(floatingPointVersion).status,
      ReasoningResponseStatus.parseFailed,
    );
  });

  test('rejects model claims of EMPTY, PARSE_FAILED, or UNKNOWN', () {
    for (final status in ['EMPTY', 'PARSE_FAILED', 'UNKNOWN']) {
      expect(
        decode(answerPayload(status: status)).status,
        ReasoningResponseStatus.parseFailed,
      );
    }
  });

  test('rejects mismatched request IDs as UNKNOWN', () {
    final result = decode(answerPayload(responseRequestId: 'other-request'));
    expect(result.status, ReasoningResponseStatus.unknown);
    expect(result.isUsable, isFalse);
  });

  test('rejects evidence IDs not supplied to the current ranked request', () {
    final result = decode(
      answerPayload(referenced: const ['invented-evidence-id']),
    );
    expect(result.status, ReasoningResponseStatus.unknown);
    expect(result.diagnostics.single, contains('UNRANKED_EVIDENCE_REFERENCE'));
  });

  test('allows omitted evidence only when it exists in the known candidate set', () {
    final accepted = decode(
      answerPayload(referenced: const [], omitted: const ['evidence-3']),
    );
    final rejected = decode(
      answerPayload(referenced: const [], omitted: const ['invented']),
    );

    expect(accepted.isUsable, isTrue);
    expect(rejected.status, ReasoningResponseStatus.unknown);
  });

  test('accepts only registered action proposals and never executes them', () {
    final payload = answerPayload(
      responseKind: 'ACTION_PROPOSAL',
      referenced: const [],
    )..['actionProposal'] = {
        'proposalId': 'proposal-1',
        'capabilityId': 'calendar.calculate',
        'arguments': {'date': '2026-11-25'},
      };
    final accepted = decode(
      payload,
      allowedCapabilities: const {'calendar.calculate'},
    );
    final rejected = decode(payload);

    expect(accepted.isUsable, isTrue);
    expect(
      accepted.response?.actionProposal?.capabilityId,
      'calendar.calculate',
    );
    expect(rejected.status, ReasoningResponseStatus.unknown);
    // A proposal is data only; this codec exposes no executor or side effect.
  });

  test('rejects authorization and execution flags inside a proposal', () {
    final payload = answerPayload(
      responseKind: 'ACTION_PROPOSAL',
      referenced: const [],
    )..['actionProposal'] = {
        'proposalId': 'proposal-1',
        'capabilityId': 'calendar.calculate',
        'arguments': {'date': '2026-11-25'},
        'authorized': true,
        'executed': true,
        'success': true,
      };

    final result = decode(
      payload,
      allowedCapabilities: const {'calendar.calculate'},
    );
    expect(result.status, ReasoningResponseStatus.parseFailed);
  });

  test('rejects action proposals attached to non-action responses', () {
    final payload = answerPayload()
      ..['actionProposal'] = {
        'proposalId': 'proposal-1',
        'capabilityId': 'calendar.calculate',
        'arguments': {'date': '2026-11-25'},
      };
    expect(
      decode(payload).status,
      ReasoningResponseStatus.parseFailed,
    );
  });

  test('rejects mismatched kind/status and duplicate evidence references', () {
    final mismatch = answerPayload(status: 'INSUFFICIENT_EVIDENCE');
    final duplicate = answerPayload(
      referenced: const ['evidence-1', 'evidence-1'],
    );

    expect(decode(mismatch).status, ReasoningResponseStatus.parseFailed);
    expect(decode(duplicate).status, ReasoningResponseStatus.parseFailed);
  });

  test('rejects invalid argument key/value types and blank values', () {
    final numeric = answerPayload(
      responseKind: 'ACTION_PROPOSAL',
      referenced: const [],
    )..['actionProposal'] = {
        'proposalId': 'proposal-1',
        'capabilityId': 'calendar.calculate',
        'arguments': {'date': 20261125},
      };
    final blank = answerPayload(
      responseKind: 'ACTION_PROPOSAL',
      referenced: const [],
    )..['actionProposal'] = {
        'proposalId': 'proposal-1',
        'capabilityId': 'calendar.calculate',
        'arguments': {'date': '  '},
      };

    expect(decode(numeric).status, ReasoningResponseStatus.parseFailed);
    expect(decode(blank).status, ReasoningResponseStatus.parseFailed);
  });
}
