import '../models/diagnosis.dart';
import '../models/tcm_interview_task_state.dart';
import '../models/zangfu_evidence.dart';
import 'tcm_interview_adapter.dart';

/// Deterministic TCM interview state machine hosted by the unified assistant
/// timeline. It owns no widgets and never asks a language model to choose
/// diagnostic answers or calculate a result.
class TcmInterviewConversationController {
  TcmInterviewConversationController({
    String? defaultGender,
    String? taskId,
  })  : _adapter = TcmInterviewAdapter(defaultGender: defaultGender),
        taskId = taskId ?? 'tcm-${DateTime.now().microsecondsSinceEpoch}';

  TcmInterviewConversationController._restored({
    required this._adapter,
    required this.taskId,
  });

  static const _temperatureQuestion =
      '你整体的寒热感觉是怎样的？（平时怕冷还是怕热，或者身体某处发凉、发热都可以告诉我）';
  static const _tonguePulseQuestion = '接下来请告诉我你的舌象和脉象（可跳过）：';

  static const Map<String, String> _zhenJiaClueKeys = {
    '面红如妆（两颧鲜红界限分明）': 'face_flush',
    '口渴欲冷饮，饮入即消': 'drink_immediate',
    '渴不欲饮或喜热饮': 'thirst_no_drink',
    '小便清长、尿色淡白': 'urine_clear',
    '小便短赤、尿色深黄': 'urine_short',
    '胸腹久按不蒸手（初按似热久按不热）': 'abdomen_cool',
    '胸腹久按蒸蒸有热气（四肢虽寒）': 'abdomen_hot',
    '大便稀溏无灼热': 'stool_loose',
    '大便硬结/肛门灼热': 'stool_burning',
  };

  final TcmInterviewAdapter _adapter;
  final String taskId;
  final List<TcmInterviewTaskMessage> _messages = [];
  final List<String> _zhenJiaSelected = [];

  String _status = 'in_progress';
  String? _pendingPromptId;
  String? _pendingPromptText;
  List<String> _pendingOptions = const [];
  bool _meridianFollowupActive = false;
  DiagnosisResult? _completedDiagnosis;

  List<TcmInterviewTaskMessage> get messages =>
      List.unmodifiable(_messages);
  String? get pendingPromptId => _pendingPromptId;
  String? get pendingPromptText => _pendingPromptText;
  List<String> get pendingOptions => List.unmodifiable(_pendingOptions);
  bool get isCompleted => _status == 'completed';
  DiagnosisResult? get completedDiagnosis => _completedDiagnosis;
  ZangFuEvidenceAssessment get currentZangFuEvidence =>
      _adapter.buildZangFuEvidence();
  bool get canAnswer => !isCompleted &&
      _pendingPromptId != null &&
      _pendingOptions.isNotEmpty;

  List<String> get tongueCoatingOptions => _adapter.tongueCoatingOptions;
  List<String> get tongueShapeOptions => _adapter.tongueShapeOptions;
  List<String> get pulseOptions => _adapter.pulseOptions;

  factory TcmInterviewConversationController.restore(
    TcmInterviewTaskState state, {
    String? defaultGender,
  }) {
    final controller = TcmInterviewConversationController._restored(
      adapter: TcmInterviewAdapter(
        snapshot: state.snapshot,
        defaultGender: defaultGender,
      ),
      taskId: state.taskId,
    );
    controller._status = state.status;
    controller._completedDiagnosis = state.completedDiagnosis;
    controller._pendingPromptId = state.pendingPromptId;
    controller._pendingPromptText = state.pendingPromptText;
    controller._pendingOptions = List<String>.unmodifiable(state.pendingOptions);
    controller._messages.addAll(state.transcript);
    for (final entry in _zhenJiaClueKeys.entries) {
      if (state.snapshot.answers['zhenjia_${entry.value}'] == true) {
        controller._zhenJiaSelected.add(entry.key);
      }
    }
    final pendingId = state.pendingPromptId;
    if (pendingId != null && pendingId.startsWith('followup:')) {
      final key = pendingId.substring('followup:'.length);
      final isPulseOrCombined = controller._adapter.pulseTongueCrossChecks
              .any((prompt) => prompt.id == key) ||
          controller._adapter.requiredCombinedPatternChecks
              .any((prompt) => prompt.id == key);
      final meridian = controller._adapter.meridianDirection ?? '少阴';
      controller._meridianFollowupActive = !isPulseOrCombined &&
          controller._adapter.followUpPrompts(meridian)
              .any((prompt) => prompt.id == key);
    }
    return controller;
  }

  /// Starts the deterministic question flow. Free-text context is preserved
  /// as a user message only; it is never silently converted into engine keys.
  void start({String? initialUserMessage, String? userContext}) {
    if (_messages.isNotEmpty || _pendingPromptId != null) {
      throw StateError('问诊任务已经启动');
    }
    if (initialUserMessage != null && initialUserMessage.trim().isNotEmpty) {
      _appendUser(initialUserMessage.trim());
    }
    if (userContext != null && userContext.trim().isNotEmpty) {
      _appendUser('已确认的症状自述（仅作上下文，未自动转换为规则答案）：\n${userContext.trim()}');
    }
    _appendAssistant(_adapter.initialGreeting);
    _askTemperature();
  }

  /// Applies one visible option and advances the state machine.
  ///
  /// Tongue/pulse entry is a dialog action and must be completed with
  /// [answerTonguePulse], not submitted as a text option.
  void answerOption(String option) {
    if (!canAnswer) throw StateError('当前没有可回答的问诊问题');
    if (!_pendingOptions.contains(option)) {
      throw ArgumentError.value(option, 'option', '不属于当前问诊选项');
    }

    final promptId = _pendingPromptId!;
    if (promptId == 'temperature') {
      final match = _adapter.temperatureOptions
          .where((item) => item.label == option);
      if (match.isEmpty) throw StateError('无法恢复当前寒热选项');
      _appendUser(option);
      _adapter.answerTemperature(match.first.key);
      _askTonguePulse();
      return;
    }

    if (promptId == 'tongue_pulse') {
      if (option == '选择舌诊脉诊') {
        throw StateError('舌诊脉诊必须通过结构化输入对话框提交');
      }
      if (option != '跳过，直接问诊') {
        throw ArgumentError.value(option, 'option', '未知舌脉选项');
      }
      _appendUser('跳过舌诊脉诊');
      _adapter.answerTonguePulse();
      _askTenQuestion();
      return;
    }

    if (promptId.startsWith('ten:')) {
      final questionId = promptId.substring(4);
      _appendUser(option);
      _adapter.answerTenQuestion(questionId, option);
      _askTenQuestion();
      return;
    }

    if (promptId == 'zhenjia') {
      if (_zhenJiaClueKeys.containsKey(option)) {
        _appendUser(option);
        _zhenJiaSelected.add(option);
        _adapter.answerZhenJia(_zhenJiaClueKeys[option]!, option);
        _askZhenJia();
      } else if (option.startsWith('没有/跳过') ||
          option.startsWith('完成鉴别')) {
        _appendUser(_zhenJiaSelected.isEmpty
            ? '跳过寒热真假鉴别'
            : '寒热真假鉴别完成（${_zhenJiaSelected.length} 条）');
        _continueAfterOptionalChecks();
      } else {
        throw ArgumentError.value(option, 'option', '未知寒热真假选项');
      }
      return;
    }

    if (promptId.startsWith('followup:')) {
      final questionId = promptId.substring('followup:'.length);
      _appendUser(option);
      _adapter.answerFollowUp(questionId, option);
      _continueAfterOptionalChecks();
      return;
    }

    throw StateError('无法识别待回答问诊问题：$promptId');
  }

  /// Commits canonical tongue/pulse values from the structured selector.
  void answerTonguePulse({
    String? tongueCoating,
    String? tongueShape,
    String? primaryPulse,
    String? secondaryPulse,
  }) {
    if (_pendingPromptId != 'tongue_pulse') {
      throw StateError('当前不在舌诊脉诊步骤');
    }
    final label = StringBuffer('舌诊脉诊：');
    if (tongueCoating != null) label.write('苔$tongueCoating ');
    if (tongueShape != null) label.write('形$tongueShape ');
    if (primaryPulse != null) label.write('脉$primaryPulse');
    if (secondaryPulse != null) label.write('兼脉$secondaryPulse');
    if (tongueCoating == null &&
        tongueShape == null &&
        primaryPulse == null &&
        secondaryPulse == null) {
      label.write('未选择');
    }
    _appendUser(label.toString());
    _adapter.answerTonguePulse(
      tongueCoating: tongueCoating,
      tongueShape: tongueShape,
      primaryPulse: primaryPulse,
      secondaryPulse: secondaryPulse,
    );
    _askTenQuestion();
  }

  TcmInterviewTaskState createTaskState() => TcmInterviewTaskState(
        taskId: taskId,
        snapshot: _adapter.createSnapshot(),
        status: _status,
        pendingPromptId: _status == 'in_progress' ? _pendingPromptId : null,
        pendingPromptText:
            _status == 'in_progress' ? _pendingPromptText : null,
        pendingOptions:
            _status == 'in_progress' ? _pendingOptions : const [],
        transcript: List.unmodifiable(_messages),
        updatedAt: DateTime.now().toUtc(),
        completedDiagnosis: _completedDiagnosis,
      );

  void _askTemperature() {
    _setPrompt(
      id: 'temperature',
      text: _temperatureQuestion,
      options: _adapter.temperatureOptions.map((item) => item.label).toList(),
    );
  }

  void _askTonguePulse() {
    _setPrompt(
      id: 'tongue_pulse',
      text: _tonguePulseQuestion,
      options: const ['选择舌诊脉诊', '跳过，直接问诊'],
    );
  }

  void _askTenQuestion() {
    final questions = _adapter.tenQuestionPrompts;
    final index = _adapter.questionIndex;
    if (index >= questions.length) {
      _afterTenQuestions();
      return;
    }
    final question = questions[index];
    _setPrompt(
      id: 'ten:${question.id}',
      text: question.question,
      options: question.options,
    );
  }

  void _afterTenQuestions() {
    if (_adapter.healthyBaselineOk) {
      _completeWithText(
        '健康基线核对结果\n\n'
        '当前回答符合 App 内置的六条健康基线条件。此结果仅表示本次问卷输入符合这些条件，'
        '不等同于医学检查或健康诊断。\n\n'
        '如有持续不适或新发症状，应及时接受正规医疗评估。',
      );
      return;
    }
    _askZhenJia();
  }

  void _askZhenJia() {
    const prompt =
        '进阶鉴别（选填）：请逐条勾选符合你的「寒热真假」线索（可多选），'
        '选完点「完成」；没有特殊线索直接点「跳过」。';
    final remaining = _zhenJiaClueKeys.keys
        .where((label) => !_zhenJiaSelected.contains(label))
        .toList(growable: false);
    _setPrompt(
      id: 'zhenjia',
      text: prompt,
      options: [
        ...remaining,
        _zhenJiaSelected.isEmpty
            ? '没有/跳过'
            : '完成鉴别（已选 ${_zhenJiaSelected.length} 条）',
      ],
    );
  }

  void _continueAfterOptionalChecks() {
    final pulseQuestions = _adapter.pulseTongueCrossChecks;
    if (pulseQuestions.isNotEmpty) {
      _askFollowUp(pulseQuestions.first);
      return;
    }

    final combinedQuestions = _adapter.requiredCombinedPatternChecks;
    if (combinedQuestions.isNotEmpty) {
      _appendAssistant('合病候选条件还缺少必要证据，先核对：');
      _askFollowUp(combinedQuestions.first);
      return;
    }

    final meridian = _adapter.meridianDirection ?? '少阴';
    final unresolvedMeridianQuestions = _adapter
        .followUpPrompts(meridian)
        .where((prompt) =>
            !_adapter.createSnapshot().answers.containsKey(prompt.id))
        .toList(growable: false);
    if (_meridianFollowupActive) {
      if (unresolvedMeridianQuestions.isNotEmpty) {
        _askFollowUp(unresolvedMeridianQuestions.first);
        return;
      }
      _meridianFollowupActive = false;
      final result = _adapter.diagnose();
      if (result != null) {
        _completeWithDiagnosis(result);
      } else {
        _completeWithText(
          '当前问诊信息仍不足以形成可复核的辨证结果。\n'
          '缺失证据不会按阴性处理，也不会据此自动推荐方剂。\n\n'
          '建议补充四诊信息，并由执业中医师面诊核实。',
        );
      }
      return;
    }

    final result = _adapter.diagnose();
    if (result != null) {
      _completeWithDiagnosis(result);
      return;
    }

    if (unresolvedMeridianQuestions.isNotEmpty) {
      _meridianFollowupActive = true;
      _appendAssistant('还需要补充少量信息，才能完成规则核对：');
      _askFollowUp(unresolvedMeridianQuestions.first);
      return;
    }

    _completeWithText(
      '当前问诊信息仍不足以形成可复核的辨证结果。\n'
      '缺失证据不会按阴性处理，也不会据此自动推荐方剂。\n\n'
      '建议补充四诊信息，并由执业中医师面诊核实。',
    );
  }

  void _askFollowUp(TcmInterviewPrompt prompt) {
    _setPrompt(
      id: 'followup:${prompt.id}',
      text: prompt.question,
      options: prompt.options,
    );
  }

  void _completeWithDiagnosis(DiagnosisResult result) {
    _completedDiagnosis = result;
    final lines = <String>[
      '辨证结果',
      '【六经】${result.displayMeridian}',
      if (result.isCombined) '【合病】${result.meridian}与${result.combinedMeridian}同病',
      '【证型】${result.pattern}',
      if (result.formula.isNotEmpty) '【方剂】${result.formula}',
      if (result.recommendedFormulas.length > 1)
        '【并列方剂】${result.recommendedFormulas.join('、')}',
      '',
      result.patternDetail,
      '',
      result.explanation,
    ];
    if (result.pulseTongueContradiction != null) {
      lines.add('\n脉舌交叉核验：${result.pulseTongueContradiction}');
    }
    final assessment = result.pulseTongueAssessment;
    if (assessment != null) {
      lines.add('\n脉舌证据状态：${assessment.status}');
      if (assessment.supportingEvidence.isNotEmpty) {
        lines.add('支持：${assessment.supportingEvidence.join('、')}');
      }
      if (assessment.contradictingEvidence.isNotEmpty) {
        lines.add('冲突：${assessment.contradictingEvidence.join('、')}');
      }
      if (assessment.missingEvidence.isNotEmpty) {
        lines.add('缺失：${assessment.missingEvidence.join('、')}');
      }
    }
    if (result.recommendConsult || result.formula.isEmpty) {
      lines.insert(1, '【状态】证据不足，不自动推荐方剂');
      lines.add('\n请由执业中医师结合四诊信息面诊核实，不要根据本结果自行用药。');
    } else {
      lines.add('\n本结果是规则引擎对已录入信息的整理，不替代执业中医师诊断和处方。');
    }

    final evidence = _adapter.buildZangFuEvidence();
    if (evidence.hasAnsweredEvidence) {
      lines.add('\n脏腑证据（原始问答）');
      for (final record in evidence.records) {
        final answer = record.answerText;
        if (answer != null) {
          lines.add('${record.questionLabel}：$answer');
        }
      }
      lines.add('脏腑归属：MISSING（没有经过逐条核验的问项—脏腑来源映射）；不输出脏腑诊断。');
    }
    _completeWithText(lines.join('\n'));
  }

  void _completeWithText(String text) {
    _status = 'completed';
    _pendingPromptId = null;
    _pendingPromptText = null;
    _pendingOptions = const [];
    _appendAssistant(text, isResult: true);
  }

  void _setPrompt({
    required String id,
    required String text,
    required List<String> options,
  }) {
    _status = 'in_progress';
    _pendingPromptId = id;
    _pendingPromptText = text;
    _pendingOptions = List.unmodifiable(options);
    _appendAssistant(text);
  }

  void _appendAssistant(String text, {bool isResult = false}) {
    _messages.add(TcmInterviewTaskMessage(
      text: text,
      isUser: false,
      isResult: isResult,
    ));
  }

  void _appendUser(String text) {
    _messages.add(TcmInterviewTaskMessage(text: text, isUser: true));
  }
}
