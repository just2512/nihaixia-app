import 'dart:convert';

import '../models/reasoning_response.dart';

/// Fail-closed decoder for the v1 E4B response envelope.
///
/// The decoder validates structure and request-local IDs only. It does not
/// resolve source IDs, authorize users, validate capability-specific argument
/// schemas, or execute a proposed action.
class ReasoningResponseCodec {
  static const int schemaVersion = 1;

  static const Set<String> _requiredKeys = {
    'schemaVersion',
    'requestId',
    'responseKind',
    'status',
    'segments',
    'referencedEvidenceIds',
    'unknowns',
    'conflicts',
    'omittedEvidenceIds',
  };

  static const Set<String> _allowedKeys = {
    ..._requiredKeys,
    'actionProposal',
    'attachmentResult',
  };

  static ReasoningResponseDecodeResult decode({
    required String raw,
    required String expectedRequestId,
    required Set<String> rankedEvidenceIds,
    required Set<String> knownEvidenceIds,
    Set<String> allowedCapabilityIds = const {},
    String? expectedAttachmentType,
  }) {
    if (raw.trim().isEmpty) {
      return _failure(ReasoningResponseStatus.empty, 'EMPTY_MODEL_RESPONSE');
    }
    if (expectedRequestId.trim().isEmpty) {
      return _failure(
        ReasoningResponseStatus.unknown,
        'EXPECTED_REQUEST_ID_MISSING',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_INVALID_JSON',
      );
    }
    if (decoded is! Map) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_ROOT_NOT_OBJECT',
      );
    }

    final payload = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        return _failure(
          ReasoningResponseStatus.parseFailed,
          'REASONING_RESPONSE_NON_STRING_KEY',
        );
      }
      final key = entry.key as String;
      if (!_allowedKeys.contains(key)) {
        return _failure(
          ReasoningResponseStatus.parseFailed,
          'REASONING_RESPONSE_UNKNOWN_FIELD:$key',
        );
      }
      payload[key] = entry.value;
    }

    final missingKeys = _requiredKeys.difference(payload.keys.toSet());
    if (missingKeys.isNotEmpty) {
      final missing = missingKeys.toList()..sort();
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_REQUIRED_FIELD_MISSING:${missing.join(',')}',
      );
    }
    if (payload['schemaVersion'] != schemaVersion) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_SCHEMA_VERSION_UNSUPPORTED',
      );
    }

    final requestId = _nonEmptyString(payload['requestId']);
    if (requestId == null) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_REQUEST_ID_INVALID',
      );
    }
    if (requestId != expectedRequestId) {
      return _failure(
        ReasoningResponseStatus.unknown,
        'REASONING_RESPONSE_REQUEST_ID_MISMATCH',
      );
    }

    final responseKind = _parseKind(payload['responseKind']);
    final declaredStatus = _parseModelStatus(payload['status']);
    final segments = _stringList(payload['segments']);
    final referencedEvidenceIds = _stringList(
      payload['referencedEvidenceIds'],
    );
    final unknowns = _stringList(payload['unknowns']);
    final conflicts = _stringList(payload['conflicts']);
    final omittedEvidenceIds = _stringList(payload['omittedEvidenceIds']);
    if (responseKind == null ||
        declaredStatus == null ||
        segments == null ||
        segments.isEmpty ||
        referencedEvidenceIds == null ||
        unknowns == null ||
        conflicts == null ||
        omittedEvidenceIds == null) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_FIELD_INVALID',
      );
    }

    if (!_allUnique(referencedEvidenceIds) ||
        !_allUnique(unknowns) ||
        !_allUnique(conflicts) ||
        !_allUnique(omittedEvidenceIds)) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_DUPLICATE_LIST_VALUE',
      );
    }

    final expectedStatus = responseKind ==
            ReasoningResponseKind.insufficientEvidence
        ? ReasoningResponseStatus.insufficientEvidence
        : ReasoningResponseStatus.completed;
    if (declaredStatus != expectedStatus) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_KIND_STATUS_MISMATCH',
      );
    }

    final unknownReferences = referencedEvidenceIds
        .where((id) => !rankedEvidenceIds.contains(id))
        .toList(growable: false);
    if (unknownReferences.isNotEmpty) {
      return _failure(
        ReasoningResponseStatus.unknown,
        'REASONING_RESPONSE_UNRANKED_EVIDENCE_REFERENCE:${unknownReferences.join(',')}',
      );
    }
    final unknownOmitted = omittedEvidenceIds
        .where((id) => !knownEvidenceIds.contains(id))
        .toList(growable: false);
    if (unknownOmitted.isNotEmpty) {
      return _failure(
        ReasoningResponseStatus.unknown,
        'REASONING_RESPONSE_UNKNOWN_OMITTED_EVIDENCE:${unknownOmitted.join(',')}',
      );
    }

    final rawAttachmentResult = payload['attachmentResult'];
    ReasoningAttachmentResult? attachmentResult;
    if (expectedAttachmentType != null) {
      attachmentResult = _parseAttachmentResult(rawAttachmentResult);
      if (attachmentResult == null || attachmentResult.attachmentType != expectedAttachmentType) {
        return _failure(ReasoningResponseStatus.parseFailed, 'REASONING_RESPONSE_ATTACHMENT_RESULT_INVALID_OR_MISMATCHED');
      }
    } else if (payload.containsKey('attachmentResult')) {
      return _failure(ReasoningResponseStatus.parseFailed, 'REASONING_RESPONSE_UNEXPECTED_ATTACHMENT_RESULT');
    }

    final rawProposal = payload['actionProposal'];
    BusinessActionProposal? proposal;
    if (responseKind == ReasoningResponseKind.actionProposal) {
      proposal = _parseProposal(rawProposal);
      if (proposal == null) {
        return _failure(
          ReasoningResponseStatus.parseFailed,
          'REASONING_RESPONSE_ACTION_PROPOSAL_INVALID',
        );
      }
      if (!allowedCapabilityIds.contains(proposal.capabilityId)) {
        return _failure(
          ReasoningResponseStatus.unknown,
          'REASONING_RESPONSE_CAPABILITY_NOT_REGISTERED',
        );
      }
    } else if (rawProposal != null) {
      return _failure(
        ReasoningResponseStatus.parseFailed,
        'REASONING_RESPONSE_UNEXPECTED_ACTION_PROPOSAL',
      );
    }

    final response = ReasoningResponse(
      requestId: requestId,
      responseKind: responseKind,
      status: declaredStatus,
      segments: segments,
      referencedEvidenceIds: referencedEvidenceIds,
      unknowns: unknowns,
      conflicts: conflicts,
      omittedEvidenceIds: omittedEvidenceIds,
      actionProposal: proposal,
      attachmentResult: attachmentResult,
    );
    return ReasoningResponseDecodeResult(
      status: declaredStatus,
      response: response,
      diagnostics: const ['REASONING_RESPONSE_V1_VALIDATED'],
    );
  }

  static ReasoningResponseDecodeResult _failure(
    ReasoningResponseStatus status,
    String diagnostic,
  ) =>
      ReasoningResponseDecodeResult(
        status: status,
        diagnostics: [diagnostic],
      );

  static ReasoningResponseKind? _parseKind(Object? value) => switch (value) {
        'ANSWER' => ReasoningResponseKind.answer,
        'CLARIFICATION' => ReasoningResponseKind.clarification,
        'ACTION_PROPOSAL' => ReasoningResponseKind.actionProposal,
        'REFUSAL' => ReasoningResponseKind.refusal,
        'INSUFFICIENT_EVIDENCE' =>
          ReasoningResponseKind.insufficientEvidence,
        _ => null,
      };

  /// EMPTY, PARSE_FAILED and UNKNOWN are runtime outcomes, not model claims.
  static ReasoningResponseStatus? _parseModelStatus(Object? value) =>
      switch (value) {
        'COMPLETED' => ReasoningResponseStatus.completed,
        'INSUFFICIENT_EVIDENCE' =>
          ReasoningResponseStatus.insufficientEvidence,
        _ => null,
      };

  static BusinessActionProposal? _parseProposal(Object? value) {
    if (value is! Map) return null;
    final keys = value.keys.toSet();
    if (keys.length != 3 ||
        !keys.contains('proposalId') ||
        !keys.contains('capabilityId') ||
        !keys.contains('arguments')) {
      return null;
    }
    final proposalId = _nonEmptyString(value['proposalId']);
    final capabilityId = _nonEmptyString(value['capabilityId']);
    final rawArguments = value['arguments'];
    if (proposalId == null || capabilityId == null || rawArguments is! Map) {
      return null;
    }
    final arguments = <String, String>{};
    for (final entry in rawArguments.entries) {
      if (entry.key is! String || entry.value is! String) return null;
      final key = (entry.key as String).trim();
      final argumentValue = entry.value as String;
      if (key.isEmpty || argumentValue.trim().isEmpty) return null;
      if (arguments.containsKey(key)) return null;
      arguments[key] = argumentValue;
    }
    return BusinessActionProposal(
      proposalId: proposalId,
      capabilityId: capabilityId,
      arguments: arguments,
    );
  }

  static ReasoningAttachmentResult? _parseAttachmentResult(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) return null;
    final type = _nonEmptyString(value['type']);
    if (type == 'image') {
      if (value.length != 2 || !value.containsKey('observations')) return null;
      final observations = _stringList(value['observations']);
      if (observations == null || observations.isEmpty || !_allUnique(observations) || observations.any((item) => item.length > 500)) return null;
      return ReasoningAttachmentResult(attachmentType: type!, observations: observations);
    }
    if (type == 'audio') {
      if (value.length != 2 || !value.containsKey('transcriptDraft')) return null;
      final draft = _nonEmptyString(value['transcriptDraft']);
      if (draft == null || draft.length > 8000) return null;
      return ReasoningAttachmentResult(attachmentType: type!, transcriptDraft: draft);
    }
    return null;
  }

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    final values = <String>[];
    for (final item in value) {
      final text = _nonEmptyString(item);
      if (text == null) return null;
      values.add(text);
    }
    return values;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static bool _allUnique(List<String> values) => values.toSet().length == values.length;
}
