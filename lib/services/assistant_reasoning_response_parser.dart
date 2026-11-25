import 'dart:convert';

import '../models/assistant_reasoning_contract.dart';

class AssistantReasoningSegment {
  const AssistantReasoningSegment({
    required this.text,
    required this.evidenceIds,
  });

  final String text;
  final List<String> evidenceIds;
}

class AssistantReasoningResponse {
  const AssistantReasoningResponse({
    required this.status,
    this.responseKind,
    this.segments = const [],
    this.referencedEvidenceIds = const [],
    this.unknowns = const [],
    this.conflicts = const [],
    this.diagnostic,
  });

  final AssistantReasoningResponseStatus status;
  final AssistantReasoningResponseKind? responseKind;
  final List<AssistantReasoningSegment> segments;
  final List<String> referencedEvidenceIds;
  final List<String> unknowns;
  final List<String> conflicts;
  final String? diagnostic;

  String get text => segments.map((segment) => segment.text).join('\n\n');

  bool get isValid =>
      status == AssistantReasoningResponseStatus.completed ||
      status == AssistantReasoningResponseStatus.insufficientEvidence ||
      status == AssistantReasoningResponseStatus.empty;

  static AssistantReasoningResponse parse({
    required String raw,
    required AssistantReasoningRequest request,
  }) {
    AssistantReasoningResponse invalid(String code) =>
        AssistantReasoningResponse(
          status: AssistantReasoningResponseStatus.parseFailed,
          diagnostic: code,
        );

    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) return invalid('ROOT_NOT_OBJECT');
      if (decoded['schemaVersion'] != 1) return invalid('SCHEMA_VERSION_MISMATCH');
      if (decoded['requestId'] != request.requestId) {
        return invalid('REQUEST_ID_MISMATCH');
      }
      final kind = AssistantReasoningResponseKind.fromWire(decoded['responseKind']);
      if (kind == null) return invalid('RESPONSE_KIND_INVALID');
      if (kind == AssistantReasoningResponseKind.actionProposal &&
          !request.allowActionProposal) {
        return invalid('ACTION_PROPOSAL_NOT_ALLOWED');
      }
      if (decoded.containsKey('actionProposal') &&
          decoded['actionProposal'] != null) {
        return invalid('ACTION_PROPOSAL_PAYLOAD_NOT_SUPPORTED_BY_THIS_ROUTE');
      }

      final rawSegments = decoded['segments'];
      if (rawSegments is! List || rawSegments.length > 64) {
        return invalid('SEGMENTS_INVALID');
      }
      final segments = <AssistantReasoningSegment>[];
      final segmentEvidenceIds = <String>{};
      for (final rawSegment in rawSegments) {
        if (rawSegment is! Map) return invalid('SEGMENT_NOT_OBJECT');
        final text = rawSegment['text'];
        final rawIds = rawSegment['evidenceIds'];
        if (text is! String ||
            text.trim().isEmpty ||
            text.length > 5000 ||
            rawIds is! List ||
            rawIds.length > 64) {
          return invalid('SEGMENT_SHAPE_INVALID');
        }
        final ids = <String>[];
        for (final rawId in rawIds) {
          if (rawId is! String ||
              !request.allowedEvidenceIds.contains(rawId) ||
              !ids.add(rawId)) {
            return invalid('SEGMENT_EVIDENCE_ID_INVALID');
          }
          segmentEvidenceIds.add(rawId);
        }
        if (kind == AssistantReasoningResponseKind.answer && ids.isEmpty) {
          return invalid('ANSWER_SEGMENT_WITHOUT_EVIDENCE');
        }
        segments.add(AssistantReasoningSegment(
          text: text.trim(),
          evidenceIds: List.unmodifiable(ids),
        ));
      }

      final rawReferenced = decoded['referencedEvidenceIds'];
      if (rawReferenced is! List || rawReferenced.length > 64) {
        return invalid('REFERENCED_EVIDENCE_IDS_INVALID');
      }
      final referenced = <String>[];
      for (final rawId in rawReferenced) {
        if (rawId is! String ||
            !request.allowedEvidenceIds.contains(rawId) ||
            !referenced.add(rawId)) {
          return invalid('REFERENCED_EVIDENCE_ID_UNKNOWN_OR_DUPLICATE');
        }
      }
      if (referenced.toSet().length != segmentEvidenceIds.length ||
          !referenced.toSet().containsAll(segmentEvidenceIds)) {
        return invalid('REFERENCED_EVIDENCE_SET_MISMATCH');
      }

      List<String>? readStrings(String key) {
        final value = decoded[key];
        if (value is! List || value.length > 32) return null;
        final output = <String>[];
        for (final item in value) {
          if (item is! String || item.trim().isEmpty || item.length > 500) {
            return null;
          }
          output.add(item.trim());
        }
        return output;
      }

      final unknowns = readStrings('unknowns');
      final conflicts = readStrings('conflicts');
      if (unknowns == null || conflicts == null) {
        return invalid('UNKNOWNS_OR_CONFLICTS_INVALID');
      }
      if (request.evidence.isEmpty &&
          kind == AssistantReasoningResponseKind.answer) {
        return invalid('ANSWER_WITHOUT_AVAILABLE_EVIDENCE');
      }
      if (kind == AssistantReasoningResponseKind.insufficientEvidence &&
          segments.isEmpty) {
        return AssistantReasoningResponse(
          status: AssistantReasoningResponseStatus.insufficientEvidence,
          responseKind: kind,
          unknowns: List.unmodifiable(unknowns),
          conflicts: List.unmodifiable(conflicts),
        );
      }
      final status = kind == AssistantReasoningResponseKind.insufficientEvidence
          ? AssistantReasoningResponseStatus.insufficientEvidence
          : segments.isEmpty
              ? AssistantReasoningResponseStatus.empty
              : AssistantReasoningResponseStatus.completed;
      return AssistantReasoningResponse(
        status: status,
        responseKind: kind,
        segments: List.unmodifiable(segments),
        referencedEvidenceIds: List.unmodifiable(referenced),
        unknowns: List.unmodifiable(unknowns),
        conflicts: List.unmodifiable(conflicts),
      );
    } on FormatException {
      return invalid('JSON_INVALID');
    } catch (_) {
      return invalid('RESPONSE_VALIDATION_FAILED');
    }
  }
}
