import '../engine/diagnostic_engine.dart';
import '../engine/diagnostic_rules.dart';
import '../models/diagnosis.dart';
import '../models/zangfu_evidence.dart';

/// Message-ready representation of one deterministic question from the
/// existing diagnostic engine. The adapter never invents clinical options.
class TcmInterviewPrompt {
  const TcmInterviewPrompt({
    required this.id,
    required this.question,
    required this.options,
    required this.source,
  });

  final String id;
  final String question;
  final List<String> options;
  final String source;
}

/// Canonical boundary between the unified conversation UI and DiagnosticEngine.
///
/// The engine remains the only owner of diagnostic rules. This adapter exposes
/// immutable prompts, validates user selections against the engine's exact
/// options, and provides a serializable engine snapshot for conversation
/// persistence. It deliberately does not use an LLM to select a diagnosis.
class TcmInterviewAdapter {
  TcmInterviewAdapter({
    DiagnosticEngine? engine,
    EngineSnapshot? snapshot,
    this.defaultGender,
  }) : _engine = engine ?? DiagnosticEngine() {
    if (snapshot != null) _engine.restoreSnapshot(snapshot);
  }

  final DiagnosticEngine _engine;
  final String? defaultGender;

  String get initialGreeting => _engine.getInitialGreeting();

  bool get healthyBaselineOk => _engine.healthyBaselineOk;

  void answerZhenJia(String key, String label) =>
      _engine.answerZhenJia(key, label);

  DiagnosticStage get stage => _engine.stage;
  int get questionIndex => _engine.tenQuestionIndex;
  String? get meridianDirection => _engine.meridianDirection;
  String? get combinedPatternCondition => _engine.combinedPatternCondition;

  EngineSnapshot createSnapshot() => _engine.createSnapshot();

  void restoreSnapshot(EngineSnapshot snapshot) =>
      _engine.restoreSnapshot(snapshot);

  List<TemperatureOption> get temperatureOptions =>
      List.unmodifiable(_engine.getTemperatureQuestions());

  void answerTemperature(String canonicalKey) {
    final allowed = _engine
        .getTemperatureQuestions()
        .any((option) => option.key == canonicalKey);
    if (!allowed) {
      throw ArgumentError.value(
        canonicalKey,
        'canonicalKey',
        '不是当前辨经引擎提供的规范选项',
      );
    }
    _engine.answerTemperaturePattern(canonicalKey);
  }

  List<String> get tongueCoatingOptions =>
      List.unmodifiable(_engine.getTongueCoatingOptions());

  List<String> get tongueShapeOptions =>
      List.unmodifiable(_engine.getTongueShapeOptions());

  List<String> get pulseOptions =>
      List.unmodifiable(_engine.getPulseOptions());

  void answerTonguePulse({
    String? tongueCoating,
    String? tongueShape,
    String? primaryPulse,
    String? secondaryPulse,
  }) {
    final canonicalCoating =
        DiagnosticRules.canonicalTongueCoating(tongueCoating);
    final canonicalShape = DiagnosticRules.canonicalTongueShape(tongueShape);
    final canonicalPrimary = DiagnosticRules.canonicalPulse(primaryPulse);
    final canonicalSecondary = DiagnosticRules.canonicalPulse(secondaryPulse);

    _rejectUnknownCanonicalValue(
      tongueCoating,
      canonicalCoating,
      'tongueCoating',
    );
    _rejectUnknownCanonicalValue(tongueShape, canonicalShape, 'tongueShape');
    _rejectUnknownCanonicalValue(primaryPulse, canonicalPrimary, 'primaryPulse');
    _rejectUnknownCanonicalValue(
      secondaryPulse,
      canonicalSecondary,
      'secondaryPulse',
    );

    _engine.answerTonguePulse(
      tongueCoating: canonicalCoating,
      tongueShape: canonicalShape,
      pulseType: canonicalPrimary,
      pulseTypeSecondary: canonicalSecondary,
    );
  }

  void _rejectUnknownCanonicalValue(
    String? raw,
    String? canonical,
    String argumentName,
  ) {
    if (raw != null && canonical == null) {
      throw ArgumentError.value(
        raw,
        argumentName,
        '不是诊断引擎提供的规范舌脉选项',
      );
    }
  }

  List<TcmInterviewPrompt> get tenQuestionPrompts {
    final before = _engine.createSnapshot();
    final effectiveGender = defaultGender ?? before.gender;
    final questions = _engine.getTenQuestions(defaultGender: effectiveGender);
    final snapshot = _engine.createSnapshot();
    final visible = snapshot.gender == 'male'
        ? questions.where((question) => question.key != 'menstrual')
        : questions;
    return visible
        .map(
          (question) => TcmInterviewPrompt(
            id: question.key,
            question: question.question,
            options: List.unmodifiable(question.options),
            source: 'diagnostic.ten_questions',
          ),
        )
        .toList(growable: false);
  }

  void answerTenQuestion(String questionId, String answer) {
    final prompt = tenQuestionPrompts.where((item) => item.id == questionId);
    if (prompt.isEmpty || !prompt.first.options.contains(answer)) {
      throw ArgumentError.value(
        answer,
        'answer',
        '答案不属于当前辨证引擎提供的规范选项',
      );
    }
    _engine.answerTenQuestion(questionId, answer);
  }

  List<TcmInterviewPrompt> get pulseTongueCrossChecks =>
      _engine.getPulseTongueFollowUpQuestions().map(_fromFollowUp).toList(
            growable: false,
          );

  List<TcmInterviewPrompt> get requiredCombinedPatternChecks =>
      _engine
          .getRequiredCombinedPatternFollowUpQuestions()
          .map(_fromFollowUp)
          .toList(growable: false);

  List<TcmInterviewPrompt> followUpPrompts(String meridian) =>
      _engine.getFollowUpQuestions(meridian).map(_fromFollowUp).toList(
            growable: false,
          );

  void answerFollowUp(String questionId, String answer) {
    final available = <TcmInterviewPrompt>[
      ...pulseTongueCrossChecks,
      ...requiredCombinedPatternChecks,
      if (meridianDirection != null) ...followUpPrompts(meridianDirection!),
    ];
    final prompt = available.where((item) => item.id == questionId);
    if (prompt.isEmpty || !prompt.first.options.contains(answer)) {
      throw ArgumentError.value(
        answer,
        'answer',
        '答案不属于当前引擎提供的追问选项',
      );
    }
    _engine.answerFollowUp(questionId, answer);
  }

  DiagnosisResult? diagnose() => _engine.diagnose();

  ZangFuEvidenceAssessment buildZangFuEvidence() =>
      _engine.buildZangFuEvidence();

  TcmInterviewPrompt _fromFollowUp(FollowUpQuestion question) =>
      TcmInterviewPrompt(
        id: question.key,
        question: question.question,
        options: List.unmodifiable(question.options),
        source: 'diagnostic.follow_up',
      );
}
