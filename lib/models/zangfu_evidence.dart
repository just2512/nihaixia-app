enum ZangFuEvidenceAnswerState {
  answered,
  explicitNormal,
  unknown,
  unanswered,
  invalid,
}

class ZangFuEvidenceRecord {
  final String questionKey;
  final String questionLabel;
  final int? optionIndex;
  final String? answerText;
  final ZangFuEvidenceAnswerState state;
  final String sourceId;

  const ZangFuEvidenceRecord({
    required this.questionKey,
    required this.questionLabel,
    required this.optionIndex,
    required this.answerText,
    required this.state,
    required this.sourceId,
  });
}

/// 原始问答证据容器。当前不含脏腑归属、证型、分值或方剂。
class ZangFuEvidenceAssessment {
  final List<ZangFuEvidenceRecord> records;
  final List<String> unclassifiedAdditionalEvidence;
  final String organMappingStatus;

  const ZangFuEvidenceAssessment({
    this.records = const [],
    this.unclassifiedAdditionalEvidence = const [],
    this.organMappingStatus = 'MISSING',
  });

  bool get hasAnsweredEvidence => records.any((record) =>
      record.state != ZangFuEvidenceAnswerState.unanswered &&
      record.state != ZangFuEvidenceAnswerState.invalid) ||
      unclassifiedAdditionalEvidence.isNotEmpty;

  bool get hasVerifiedOrganMapping => organMappingStatus == 'VERIFIED';
}
