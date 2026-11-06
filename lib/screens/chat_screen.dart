import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../engine/diagnostic_engine.dart';
import '../engine/diagnostic_rules.dart';
import '../engine/meridian_formula_types.dart';
import '../data/formula_repository.dart';
import '../data/formula_oral_hint_repository.dart';
import '../data/settings_repository.dart';
import '../models/diagnosis.dart';
import '../models/tcm_interview_task_state.dart';
import '../models/zangfu_evidence.dart';
import '../models/bookmark.dart';
import '../services/tcm_interview_adapter.dart';
import '../data/database_helper.dart';
import 'formula_detail_screen.dart';
import 'meridian_detail_screen.dart';
import '../models/formula.dart';
import '../widgets/oral_hint_card.dart';
import 'settings_screen.dart';
import '../theme/app_tokens.dart';

/// 高危禁忌关键词（用于结果卡红色强提示）
const Set<String> _highRiskKeywords = {
  '孕妇', '妊娠', '哺乳', '亡阳', '阳虚欲脱', '大出血',
  '真寒假热', '真热假寒', '禁用', '忌用',
};

bool _isHighRiskContraindication(String text) {
  if (text.isEmpty) return false;
  return _highRiskKeywords.any((k) => text.contains(k));
}

/// 对话步骤快照（用于返回上一步）
class _StepSnapshot {
  final List<_ChatBubble> messages;
  final EngineSnapshot engineSnapshot;
  final List<_ChatOption> options;
  final String? pendingPromptId;
  final String? pendingPromptText;

  _StepSnapshot({
    required this.messages,
    required this.engineSnapshot,
    required this.options,
    this.pendingPromptId,
    this.pendingPromptText,
  });
}

class ChatScreen extends StatefulWidget {
  final bool returnResultOnComplete;
  final String? initialUserContext;
  final TcmInterviewTaskState? initialTaskState;
  final Future<void> Function(TcmInterviewTaskState state)? onTaskStateChanged;

  const ChatScreen({
    super.key,
    this.returnResultOnComplete = false,
    this.initialUserContext,
    this.initialTaskState,
    this.onTaskStateChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DiagnosticEngine _engine = DiagnosticEngine();
  late final TcmInterviewAdapter _interview =
      TcmInterviewAdapter(engine: _engine);
  final List<_ChatBubble> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _showOptions = false;
  List<_ChatOption> _currentOptions = [];
  bool _canGoBack = false;

  // P2-3 自由文本症状/方剂搜索
  final TextEditingController _searchController = TextEditingController();
  List<Formula> _searchResults = [];
  bool _searchExpanded = false;

  // 诊断步骤历史栈（用于返回上一步）
  final List<_StepSnapshot> _stepHistory = [];
  String? _pendingPromptId;
  String? _pendingPromptText;
  late final String _taskId = widget.initialTaskState?.taskId ??
      'tcm-${DateTime.now().microsecondsSinceEpoch}';

  // 舌诊脉诊选择状态
  String? _selectedTongueCoating;
  String? _selectedTongueShape;
  String? _selectedPulse;
  String? _selectedPulseSecondary;

  @override
  void initState() {
    super.initState();
    final initialTask = widget.initialTaskState;
    if (initialTask != null && initialTask.status == 'in_progress') {
      _restorePendingTaskState(initialTask);
    } else {
      _startDiagnosis();
    }
  }

  void _startDiagnosis() {
    // initState 阶段直接构造首屏状态，避免调用 _addBotMessage /
    // _showTemperatureOptions 中的 setState 导致首帧状态更新异常。
    final initialContext = widget.initialUserContext?.trim();
    if (initialContext != null && initialContext.isNotEmpty) {
      _messages.add(
        _ChatBubble(
          text: '已从 AI 助手带入本次用户自述（仅作核对上下文，不自动映射为辨证选项）：\n'
              '$initialContext',
          isUser: false,
        ),
      );
    }
    _messages.add(
      _ChatBubble(text: _engine.getInitialGreeting(), isUser: false),
    );
    const question =
        '你整体的寒热感觉是怎样的？（平时怕冷还是怕热，或者身体某处发凉、发热都可以告诉我）';
    _messages.add(_ChatBubble(text: question, isUser: false));
    _currentOptions = _engine
        .getTemperatureQuestions()
        .map((option) => _ChatOption(
              label: option.label,
              description: option.description,
              onTap: () => _selectTemperature(option.key, option.label),
            ))
        .toList();
    _showOptions = true;
    _pendingPromptId = 'temperature';
    _pendingPromptText = question;
    _emitTaskState();
  }

  void _emitTaskState({String status = 'in_progress'}) {
    final callback = widget.onTaskStateChanged;
    if (callback == null) return;
    final state = TcmInterviewTaskState(
      taskId: _taskId,
      snapshot: _interview.createSnapshot(),
      status: status,
      pendingPromptId: status == 'in_progress' ? _pendingPromptId : null,
      pendingPromptText: status == 'in_progress' ? _pendingPromptText : null,
      pendingOptions: status == 'in_progress'
          ? _currentOptions.map((option) => option.label).toList(growable: false)
          : const [],
      updatedAt: DateTime.now().toUtc(),
    );
    unawaited(() async {
      try {
        await callback(state);
      } catch (error) {
        debugPrint('[TcmInterviewTask] 保存问诊状态失败：$error');
      }
    }());
  }

  void _restorePendingTaskState(TcmInterviewTaskState state) {
    _interview.restoreSnapshot(state.snapshot);
    _pendingPromptId = state.pendingPromptId;
    _pendingPromptText = state.pendingPromptText;
    final promptText = state.pendingPromptText;
    if (promptText == null || promptText.isEmpty || state.pendingPromptId == null) {
      _messages.add(const _ChatBubble(
        text: '已恢复问诊数据，但当前记录缺少待回答问题，无法安全继续。原有问诊状态保持不变，请勿覆盖；可重新开始一项问诊。',
        isUser: false,
      ));
      return;
    }
    _messages.add(_ChatBubble(text: promptText, isUser: false));
    final id = state.pendingPromptId!;
    final savedOptions = state.pendingOptions;
    if (id == 'temperature') {
      _currentOptions = _engine.getTemperatureQuestions()
          .where((option) => savedOptions.contains(option.label))
          .map((option) => _ChatOption(
                label: option.label,
                description: option.description,
                onTap: () => _selectTemperature(option.key, option.label),
              )).toList();
    } else if (id == 'tongue_pulse') {
      _currentOptions = [
        _ChatOption(label: '选择舌诊脉诊', icon: Icons.edit_note, onTap: _showTonguePulseDialog),
        _ChatOption(label: '跳过，直接问诊', icon: Icons.skip_next, onTap: () {
          _addUserMessage('跳过舌诊脉诊');
          _interview.answerTonguePulse();
          _showTenQuestion(0);
        }),
      ];
    } else if (id.startsWith('ten:')) {
      final key = id.substring(4);
      final questions = _engine.getTenQuestions(
        defaultGender: SettingsRepository.instance.defaultGender,
      );
      final index = questions.indexWhere((question) => question.key == key);
      if (index >= 0) {
        final question = questions[index];
        _currentOptions = question.options.where(savedOptions.contains).map((answer) =>
          _ChatOption(label: answer, number: index + 1, onTap: () {
            _addUserMessage(answer);
            _interview.answerTenQuestion(question.key, answer);
            _showTenQuestion(_engine.tenQuestionIndex);
          }),
        ).toList();
      }
    } else if (id == 'zhenjia') {
      for (final entry in _zhenJiaClueKeys.entries) {
        if (_engine.createSnapshot().answers['zhenjia_${entry.value}'] == true &&
            !_zhenJiaSelected.contains(entry.key)) {
          _zhenJiaSelected.add(entry.key);
        }
      }
      _currentOptions = [
        for (final entry in _zhenJiaClueKeys.entries)
          if (!_zhenJiaSelected.contains(entry.key) && savedOptions.contains(entry.key))
            _ChatOption(label: entry.key, onTap: () => _selectZhenJia(entry.key, entry.value)),
        _ChatOption(
          label: savedOptions.lastWhere((option) => option.startsWith('没有/跳过') || option.startsWith('完成鉴别'), orElse: () => '没有/跳过'),
          icon: Icons.check,
          onTap: _finishZhenJia,
        ),
      ];
    } else if (id.startsWith('followup:')) {
      final key = id.substring(9);
      final candidates = <FollowUpQuestion>[
        ..._engine.getPulseTongueFollowUpQuestions(),
        ..._engine.getRequiredCombinedPatternFollowUpQuestions(),
        if (_engine.meridianDirection != null)
          ..._engine.getFollowUpQuestions(_engine.meridianDirection!),
      ];
      final matching = candidates.where((question) => question.key == key);
      if (matching.isNotEmpty) {
        final question = matching.first;
        _currentOptions = question.options.where(savedOptions.contains).map((answer) =>
          _ChatOption(label: answer, onTap: () {
            _addUserMessage(answer);
            _interview.answerFollowUp(question.key, answer);
            _proceedAfterZhenJia();
          }),
        ).toList();
      }
    }
    _showOptions = _currentOptions.isNotEmpty;
    if (!_showOptions) {
      _messages.add(const _ChatBubble(
        text: '当前版本无法重建这道问诊题的选项。原始问诊数据已保留，没有自动改写或丢弃。',
        isUser: false,
      ));
    }
  }

  // ==================== 快照管理 ====================

  void _saveSnapshot() {
    _stepHistory.add(_StepSnapshot(
      messages: List.from(_messages),
      engineSnapshot: _interview.createSnapshot(),
      options: List.of(_currentOptions),
      pendingPromptId: _pendingPromptId,
      pendingPromptText: _pendingPromptText,
    ));
    _canGoBack = true;
  }

  void _goBack() {
    if (_stepHistory.isEmpty) return;
    final snapshot = _stepHistory.removeLast();
    setState(() {
      _messages.clear();
      _messages.addAll(snapshot.messages);
      _interview.restoreSnapshot(snapshot.engineSnapshot);
      _currentOptions = snapshot.options;
      _pendingPromptId = snapshot.pendingPromptId;
      _pendingPromptText = snapshot.pendingPromptText;
      _showOptions = true;
      _canGoBack = _stepHistory.isNotEmpty;
    });
    _emitTaskState();
    _scrollToBottom();
  }

  // ==================== 寒热辨经 ====================

  void _showTemperatureOptions() {
    final question =
        '你整体的寒热感觉是怎样的？（平时怕冷还是怕热，或者身体某处发凉、发热都可以告诉我）';
    _addBotMessage(question);
    final options = _engine.getTemperatureQuestions();
    _pendingPromptId = 'temperature';
    _pendingPromptText = question;
    setState(() {
      _currentOptions = options
          .map((o) => _ChatOption(
                label: o.label,
                description: o.description,
                onTap: () => _selectTemperature(o.key, o.label),
              ))
          .toList();
      _showOptions = true;
    });
    _emitTaskState();
  }

  void _selectTemperature(String key, String label) {
    _saveSnapshot();
    _addUserMessage(label);
    _interview.answerTemperature(key);
    _showTonguePulseInput();
  }

  // ==================== 舌诊脉诊 ====================

  void _showTonguePulseInput() {
    const prompt = '接下来请告诉我你的舌象和脉象（可跳过）：';
    _pendingPromptId = 'tongue_pulse';
    _pendingPromptText = prompt;
    _addBotMessage(prompt);
    setState(() {
      _currentOptions = [
        _ChatOption(
          label: '选择舌诊脉诊',
          icon: Icons.edit_note,
          onTap: _showTonguePulseDialog,
        ),
        _ChatOption(
          label: '跳过，直接问诊',
          icon: Icons.skip_next,
          onTap: () {
            _addUserMessage('跳过舌诊脉诊');
            _interview.answerTonguePulse();
            _showTenQuestion(0);
          },
        ),
      ];
      _showOptions = true;
    });
    _emitTaskState();
  }

  void _showTonguePulseDialog() {
    _selectedTongueCoating = null;
    _selectedTongueShape = null;
    _selectedPulse = null;
    _selectedPulseSecondary = null;

    showFoldAwareDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('舌诊脉诊'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('舌苔', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _engine.getTongueCoatingOptions().map((opt) {
                    final selected = _selectedTongueCoating == opt;
                    return FilterChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: (s) {
                        setDialogState(() {
                          _selectedTongueCoating = s ? opt : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('舌形', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _engine.getTongueShapeOptions().map((opt) {
                    final selected = _selectedTongueShape == opt;
                    return FilterChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: (s) {
                        setDialogState(() {
                          _selectedTongueShape = s ? opt : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('主脉象', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _engine.getPulseOptions().map((opt) {
                    final selected = _selectedPulse == opt;
                    return FilterChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: (s) {
                        setDialogState(() {
                          _selectedPulse = s ? opt : null;
                          // A secondary pulse is meaningful only alongside a
                          // distinct primary pulse. Clear stale secondary input
                          // if the primary is removed or changed to the same value.
                          if (_selectedPulse == null ||
                              _selectedPulseSecondary == _selectedPulse) {
                            _selectedPulseSecondary = null;
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('兼脉（选填；须与主脉不同，且只有两项同时填写才识别组合脉）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _engine.getPulseOptions().map((opt) {
                    final selected = _selectedPulseSecondary == opt;
                    return FilterChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: _selectedPulse == null ||
                              _selectedPulse == opt
                          ? null
                          : (s) {
                              setDialogState(() {
                                _selectedPulseSecondary = s ? opt : null;
                              });
                            },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _saveSnapshot();
                String label = '舌诊脉诊：';
                if (_selectedTongueCoating != null) label += '苔${_selectedTongueCoating!} ';
                if (_selectedTongueShape != null) label += '形${_selectedTongueShape!} ';
                if (_selectedPulse != null) label += '脉${_selectedPulse!}';
                if (_selectedPulseSecondary != null) label += '兼脉${_selectedPulseSecondary!}';
                if (_selectedTongueCoating == null &&
                    _selectedTongueShape == null &&
                    _selectedPulse == null &&
                    _selectedPulseSecondary == null) {
                  label = '舌诊脉诊：未选择';
                }
                _addUserMessage(label);
                _interview.answerTonguePulse(
                  tongueCoating: _selectedTongueCoating,
                  tongueShape: _selectedTongueShape,
                  primaryPulse: _selectedPulse,
                  secondaryPulse: _selectedPulseSecondary,
                );
                _showTenQuestion(0);
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 倪海厦九问 ====================

  void _showTenQuestion(int index) {
    final settings = SettingsRepository.instance;
    final questions = _engine.getTenQuestions(defaultGender: settings.defaultGender);
    if (index >= questions.length) {
      _afterTenQuestions();
      return;
    }

    final q = questions[index];
    _pendingPromptId = 'ten:${q.key}';
    _pendingPromptText = q.question;
    _addBotMessage(q.question);
    setState(() {
      _currentOptions = q.options
          .map((o) => _ChatOption(
                label: o,
                number: index + 1,
                onTap: () {
                  _saveSnapshot();
                  _addUserMessage(o);
                  _interview.answerTenQuestion(q.key, o);
                  // The engine may skip gender-specific questions; follow its
                  // canonical index instead of incrementing the UI index.
                  _showTenQuestion(_engine.tenQuestionIndex);
                },
              ))
          .toList();
      _showOptions = true;
    });
    _emitTaskState();
  }

  // ==================== 九问后处理 ====================

  void _afterTenQuestions() {
    // v1.11.8 ① 健康人基线：六条全过 → 正面反馈，不进入异常辨证
    if (_engine.healthyBaselineOk) {
      _showHealthyBaselineResult();
      return;
    }
    // v1.11.8 ③ 寒热真假八维法（选填，可多选/跳过）
    _showZhenJiaOptions();
  }

  /// v1.11.8 ① 倪师六条健康基线全部达标 → 正面反馈。
  void _showHealthyBaselineResult() {
    const baselineText = '恭喜，你是个正常人\n\n'
        '倪师六条健康基线全部达标：\n'
        '• 一觉到天亮，中间不醒\n'
        '• 晨起正常排便，成形\n'
        '• 小便淡黄，一天 5-7 次\n'
        '• 手脚温热\n'
        '• 有胃口，食之有味\n'
        '• 早起床精神好\n\n'
        '继续保持：不熬夜、忌生冷、七分饱、顺应时辰。';
    _pendingPromptId = null;
    _pendingPromptText = null;
    _addBotMessage(baselineText, isResult: true);
    setState(() {
      _currentOptions = [
        _ChatOption(label: '重新辨证', icon: Icons.refresh, onTap: _resetDiagnosis),
      ];
      _showOptions = true;
    });
    _emitTaskState(status: 'completed');
  }

  // ==================== v1.11.8 ③ 寒热真假八维法（选填） ====================

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
  final List<String> _zhenJiaSelected = [];

  void _showZhenJiaOptions() {
    const prompt = '进阶鉴别（选填）：请逐条勾选符合你的「寒热真假」线索（可多选），'
        '选完点「完成」；没有特殊线索直接点「跳过」。';
    _pendingPromptId = 'zhenjia';
    _pendingPromptText = prompt;
    _addBotMessage(prompt);
    setState(() {
      _currentOptions = [
        for (final e in _zhenJiaClueKeys.entries)
          if (!_zhenJiaSelected.contains(e.key))
            _ChatOption(label: e.key, onTap: () => _selectZhenJia(e.key, e.value)),
        _ChatOption(
          label: _zhenJiaSelected.isEmpty ? '没有/跳过' : '完成鉴别（已选 ${_zhenJiaSelected.length} 条）',
          icon: Icons.check,
          onTap: _finishZhenJia,
        ),
      ];
      _showOptions = true;
    });
    _emitTaskState();
  }

  void _selectZhenJia(String label, String key) {
    _saveSnapshot();
    _addUserMessage(label);
    _zhenJiaSelected.add(label);
    _engine.answerZhenJia(key, label);
    _showZhenJiaOptions();
  }

  void _finishZhenJia() {
    _addUserMessage(
        _zhenJiaSelected.isEmpty ? '跳过寒热真假鉴别' : '寒热真假鉴别完成（${_zhenJiaSelected.length} 条）');
    _proceedAfterZhenJia();
  }

  /// 寒热真假选填结束后，进入正式诊断（原 _afterTenQuestions 的 diagnose 逻辑）。
  void _proceedAfterZhenJia() {
    final pulseQuestions = _engine.getPulseTongueFollowUpQuestions();
    if (pulseQuestions.isNotEmpty) {
      _addBotMessage('脉象、舌象与问诊信息存在待核对项，先补充必要信息：');
      _showFollowUpQuestion(pulseQuestions, 0, onComplete: _proceedAfterZhenJia);
      return;
    }

    // 合病规则需要的条文前提必须在最终结果前逐项核对；未知不按阴性处理。
    final requiredCombinedQuestions =
        _engine.getRequiredCombinedPatternFollowUpQuestions();
    if (requiredCombinedQuestions.isNotEmpty) {
      _addBotMessage('合病候选条件还缺少必要证据，先核对：');
      _showFollowUpQuestion(
        requiredCombinedQuestions,
        0,
        onComplete: _proceedAfterZhenJia,
      );
      return;
    }

    final result = _interview.diagnose();
    if (result != null) {
      _addBotMessage('好，十问已经完成了。让我根据你的情况来分析...\n\n'
          '你的情况：${_engine.selectedSymptoms.join("、")}\n\n'
          '下面给出辨证结果：');
      _showResult();
    } else {
      _addBotMessage('好的，让我进一步确认一些症状...');
      final meridian = _engine.meridianDirection ?? '少阴';
      final questions = _engine.getFollowUpQuestions(meridian);
      if (questions.isNotEmpty) {
        _showFollowUpQuestion(questions, 0);
      } else {
        _showResult();
      }
    }
  }

  void _showFollowUpQuestion(
    List<FollowUpQuestion> questions,
    int index, {
    VoidCallback? onComplete,
  }) {
    if (index >= questions.length) {
      if (onComplete != null) {
        onComplete();
      } else {
        _showResult();
      }
      return;
    }

    final q = questions[index];
    _pendingPromptId = 'followup:${q.key}';
    _pendingPromptText = q.question;
    _addBotMessage(q.question);
    setState(() {
      _currentOptions = q.options
          .map((o) => _ChatOption(
                label: o,
                onTap: () {
                  _saveSnapshot();
                  _addUserMessage(o);
                  _interview.answerFollowUp(q.key, o);
                  _showFollowUpQuestion(
                    questions,
                    index + 1,
                    onComplete: onComplete,
                  );
                },
              ))
          .toList();
      _showOptions = true;
    });
    _emitTaskState();
  }

  // ==================== 诊断结果展示 ====================

  void _returnDiagnosisToAssistant() {
    _emitTaskState(status: 'completed');
    final summary = _messages
        .map((message) => message.text)
        .where((text) => text.trim().isNotEmpty)
        .join('\n\n');
    Navigator.pop(context, summary);
  }

  void _showResult() {
    final result = _interview.diagnose();
    if (result == null) return;

    _pendingPromptId = null;
    _pendingPromptText = null;
    _emitTaskState(status: 'completed');
    setState(() => _showOptions = false);

    // 脏腑证据层当前只展示 App 原始问答；未经经典来源核验的脏腑归属保持 MISSING。
    final zangFuEvidence = _interview.buildZangFuEvidence();
    if (zangFuEvidence.hasAnsweredEvidence) {
      const questionLabels = <String, String>{
        'temperature': '寒热',
        'pulse': '脉象',
        'thirst': '渴饮',
        'sweating': '汗出',
        'pain': '疼痛',
        'stool': '大便',
        'urine': '小便',
        'appetite': '胃口',
        'sleep': '睡眠',
        'energy': '精神',
        'menstrual': '月经/性功能',
        'vomit_type': '呕吐类型',
        'tongue_coating': '舌苔',
        'tongue_shape': '舌形',
        'pulse_type': '主脉',
        'pulse_type_secondary': '兼脉',
        'treatment_history': '既往误治',
        'combined_treatment_history': '既往误用泻下法',
        'sun_taiyin_repeated_purgation': '反复泻下史',
        'sun_taiyin_epigastric_hard': '心下痞硬',
        'food_stagnation': '食积线索',
      };
      final evidenceLines = <String>[];
      for (final record in zangFuEvidence.records) {
        final label = questionLabels[record.questionKey] ?? record.questionLabel;
        final stateLabel = switch (record.state) {
          ZangFuEvidenceAnswerState.explicitNormal => '（明确正常项）',
          ZangFuEvidenceAnswerState.unknown => '（未知/不确定）',
          ZangFuEvidenceAnswerState.answered => '',
          ZangFuEvidenceAnswerState.unanswered => '（未作答）',
          ZangFuEvidenceAnswerState.invalid => '（选项无效）',
        };
        final answer = record.answerText;
        if (answer == null) {
          if (record.state == ZangFuEvidenceAnswerState.unanswered ||
              record.state == ZangFuEvidenceAnswerState.invalid) {
            evidenceLines.add('$label：$stateLabel');
          }
          continue;
        }
        evidenceLines.add('$label：$answer$stateLabel');
      }
      if (zangFuEvidence.unclassifiedAdditionalEvidence.isNotEmpty) {
        evidenceLines.add(
          '其他自述：${zangFuEvidence.unclassifiedAdditionalEvidence.join('、')}',
        );
      }
      if (evidenceLines.isNotEmpty) {
        _addBotMessage(
          '脏腑证据层（原始问答）\n'
          '${evidenceLines.join('\n')}\n\n'
          '脏腑归属：MISSING（尚无逐条核验的问项—脏腑来源映射）。'
          '这里只保留原始问答，不作脏腑诊断、排序或方剂推断。',
          isResult: false,
        );
      }
    }

    // P0-2: 证据不足，建议面诊（不强行给方，避免误治）
    if (result.recommendConsult || result.formula.isEmpty) {
      _addBotMessage(
        '辨证依据不足\n\n'
        '${result.explanation}\n\n'
        '（本结果仅供参考，请线下就诊由执业中医师四诊合参）',
        isWarning: true,
      );

      if (_engine.suppressReferenceFormulaSuggestions) {
        _addBotMessage(
          '该条文未直接载明可自动推荐的方剂，或当前方剂关联来源待核。'
          '为避免用相似度检索绕过来源闸门，本次不显示参考方剂。',
          isWarning: true,
        );
      } else {
        // 普通证据不足场景仍可显示明确标记的关键词参考；来源待核的
        // 空方剂规则必须 fail-closed，不能由相似度候选重新引入方剂。
        final tableSuggestion = _engine.suggestByTable();
        final ranking = _engine.getSimilarityRanking(topK: 3);
        final refNames = <String>{};
        if (tableSuggestion != null) refNames.add(tableSuggestion);
        for (final (name, _) in ranking) {
          refNames.add(name);
        }
        if (refNames.isNotEmpty) {
          _addBotMessage(
            '相似症状参考方（非处方，仅供参考）\n\n'
            '${refNames.take(3).join('、')}\n\n'
            '以上仅依据症状关键词匹配，未经正式辨证，切勿自行用药；'
            '请线下就诊由执业中医师四诊合参后处方。',
          );
        }
      }

      _addBotMessage('想重新辨证吗？');
      setState(() {
        _currentOptions = [
          _ChatOption(label: '重新辨证', icon: Icons.refresh, onTap: _resetDiagnosis),
          _ChatOption(label: '分享', icon: Icons.share, onTap: () => _shareResult(result)),
          if (widget.returnResultOnComplete)
            _ChatOption(label: '返回 AI 助手', icon: Icons.reply, onTap: _returnDiagnosisToAssistant),
        ];
        _showOptions = true;
      });
      return;
    }

    final formula = FormulaRepository.getByName(result.formula);
    final explanation = formula?.explanation ?? result.explanation;

    // L1：若主方剂有「患者口语」语料，则在结果气泡下方附「患者会怎么说」卡片，
    // 让用户对照大白话、提升辨证结果的可解释性。语料未覆盖时为 null（不渲染）。
    Widget? oralHintCard;
    if (formula != null) {
      final hint = FormulaOralHintRepository.getById(formula.id);
      if (hint != null && hint.oral.isNotEmpty) {
        oralHintCard = OralHintCard(hint: hint);
      }
    }

    String resultText = '辨证结果\n\n'
        '【六经】${result.displayMeridian}病\n';

    if (result.isCombined) {
      resultText += '合病：${result.meridian}与${result.combinedMeridian}同病\n';
    }

    resultText += '【证型】${result.pattern}\n'
        '【方剂】${result.formula}\n';

    // v3.2：必选症状相同的多个方剂同时推荐（不再静默只取一个）
    final coFormulas = result.recommendedFormulas
        .where((n) => n != result.formula)
        .toList();
    if (coFormulas.isNotEmpty) {
      resultText += '【同症并列推荐】${coFormulas.join('、')}\n';
    }

    if (formula != null && formula.components.isNotEmpty) {
      resultText += '【组成】${formula.componentsText}\n';
    }

    // 舌诊脉诊信息
    if (result.tongueCoating != null || result.tongueShape != null || result.pulseType != null) {
      resultText += '\n舌脉：';
      if (result.tongueCoating != null) resultText += '苔${result.tongueCoating} ';
      if (result.tongueShape != null) resultText += '形${result.tongueShape} ';
      if (result.pulseType != null) resultText += '脉${result.pulseType}';
      if (result.pulseTypeSecondary != null) resultText += '兼脉${result.pulseTypeSecondary}';
      resultText += '\n';
    }

    // 未提供脉象（普通用户不会摸脉是常态）→ 标注参考性
    if (result.pulseType == null) {
      resultText += '未提供脉象信息，本次结论仅供参考\n';
    }

    resultText += '\n${result.patternDetail}\n\n$explanation';

    // P1-3: 推理链（简单/详细模式均显示）
    final reasoning = result.matchedSymptoms.isNotEmpty
        ? result.matchedSymptoms
        : _engine.selectedSymptoms;
    if (reasoning.isNotEmpty) {
      resultText += '\n\n判定依据\n'
          '关键输入：${reasoning.join('、')}\n'
          '→ 归入 ${result.displayMeridian}病 · ${result.pattern}';
    }

    _addBotMessage(resultText,
        isResult: true, diagnosisResult: result, extra: oralHintCard);

    // P1-4: 高危方红色强提示（简单/详细模式均显示）
    final contraindicationText =
        formula?.contraindication ?? result.prescription?.contraindication ?? '';
    if (_isHighRiskContraindication(contraindicationText)) {
      _addBotMessage(
        '用药安全警示\n\n'
        '本方禁忌：$contraindicationText\n\n'
        '含高危人群/证型提示，使用前务必咨询执业中医师，切勿自行用药。',
        isWarning: true,
      );
    }

    // 自动复制处方
    if (result.prescription != null && SettingsRepository.instance.autoCopyPrescription) {
      final text = result.prescription!.toCopyText();
      Clipboard.setData(ClipboardData(text: text));
      _addBotMessage('处方已自动复制到剪贴板');
    }

    // 保存诊断历史
    DatabaseHelper.instance.saveDiagnosisHistory(
      result.meridian,
      result.pattern,
      result.formula,
      result.confidence,
      jsonEncode(result.answers),
    );

    // 详细模式：显示完整诊断信息；简单模式：只显示基本结果
    final isDetailed = SettingsRepository.instance.diagnosticLevel == 'detailed';

    // ==================== v1.11.8 ② 用药铁律（安全信息，不分简单/详细模式） ====================

    // P0-4: 用药铁律
    if (result.medicationRules != null && result.medicationRules!.isNotEmpty) {
      String mrText = '用药铁律\n';
      for (final rule in result.medicationRules!) {
        mrText += '\n• ${rule.condition}：${rule.prohibition}';
        mrText += '\n  原因：${rule.reason}';
        mrText += '\n  误治急救：${rule.emergencyTreatment}';
      }
      _addBotMessage(mrText, isResult: false);
    }

    // P0-5: 汗法禁忌
    if (result.sweatingContraindications != null && result.sweatingContraindications!.isNotEmpty) {
      String scText = '汗法禁忌\n';
      for (final sc in result.sweatingContraindications!) {
        scText += '\n• ${sc.condition}：${sc.reason}（后果：${sc.consequence}）';
      }
      _addBotMessage(scText, isResult: false);
    }

    if (isDetailed) {
    // P0-2: 脉舌矛盾警告
    if (result.pulseTongueContradiction != null) {
      _addBotMessage('脉舌交叉核验\n${result.pulseTongueContradiction}', isResult: false);
    }
    final crossCheck = result.pulseTongueAssessment;
    if (crossCheck != null) {
      final lines = <String>['状态：${crossCheck.status}'];
      if (crossCheck.supportingEvidence.isNotEmpty) {
        lines.add('支持线索：${crossCheck.supportingEvidence.join('、')}');
      }
      if (crossCheck.contradictingEvidence.isNotEmpty) {
        lines.add('反证线索：${crossCheck.contradictingEvidence.join('、')}');
      }
      if (crossCheck.missingEvidence.isNotEmpty) {
        lines.add('缺失线索：${crossCheck.missingEvidence.join('、')}');
      }
      _addBotMessage(lines.join('\n'), isResult: false);
    }

    // P0-1: 真寒假热/真热假寒
    if (result.trueFalseHeatCold != null) {
      final tfhc = result.trueFalseHeatCold!;
      String tfhcText = '${tfhc.type}八维鉴别\n\n${tfhc.description}\n';
      for (final entry in tfhc.dimensions.entries) {
        tfhcText += '\n• ${entry.key}：${entry.value}';
      }
      _addBotMessage(tfhcText, isResult: false);
    }

    // P1-4: 组合脉象
    if (result.pulseCombination != null) {
      final pc = result.pulseCombination!;
      _addBotMessage('组合脉象：${pc.pulse1}+${pc.pulse2}\n'
          '指向${pc.meridian}经 → ${pc.formula}\n${pc.description}', isResult: false);
    }

    // 处方详情
    if (result.prescription != null) {
      final rx = result.prescription!;
      String rxText = '完整处方\n'
          '─────────────────\n'
          '${rx.components.map((c) => '${c.name} ${c.dosage}').join('  ')}';

      if (rx.preparation.isNotEmpty) {
        rxText += '\n\n煎服法:\n${rx.preparation}';
      }
      if (rx.contraindication.isNotEmpty) {
        rxText += '\n\n禁忌:\n${rx.contraindication}';
      }
      if (rx.modifications != null && rx.modifications!.isNotEmpty) {
        rxText += '\n\n加减建议:';
        for (final m in rx.modifications!) {
          rxText += '\n• ${m.condition} → ${m.description}';
          if (m.resultFormula.isNotEmpty) {
            rxText += '（${m.resultFormula}）';
          }
        }
      }
      _addBotMessage(rxText, isResult: false);
    }

    // 鉴别诊断
    if (result.differential != null) {
      final diff = result.differential!;
      String diffText = '鉴别诊断\n\n'
          '【关键区别】${diff.keyDifference}\n\n'
          '┌─ ${diff.name1}（${diff.formula1}）\n'
          '│  ${diff.details.entries.map((e) => '${e.key}：${e.value}').join('\n│  ')}\n'
          '│\n'
          '└─ ${diff.name2}（${diff.formula2}）\n'
          '   ${diff.details.entries.map((e) => '${e.key}：${e.value}').join('\n   ')}';
      _addBotMessage(diffText, isResult: false);
    }

    // P1-3: 瘀血五法
    if (result.bloodStasisSigns != null && result.bloodStasisSigns!.isNotEmpty) {
      String bsText = '瘀血诊断（五法）\n';
      for (final sign in result.bloodStasisSigns!) {
        bsText += '\n• ${sign.method}：${sign.description}';
      }
      _addBotMessage(bsText, isResult: false);
    }

    // P0-4: 用药铁律（已上移至详细/简单模式均展示）
    // P0-5: 汗法禁忌（已上移至详细/简单模式均展示）

    // P1-7: 传经判断
    if (result.transmission != null) {
      final t = result.transmission!;
      _addBotMessage('传经预警\n'
          '${t.from}→${t.to}传经信号：${t.sign}\n'
          '治疗原则：${t.treatment}', isResult: false);
    }

    // 传经预警文本（来自七步走第四步：判传变）
    if (result.transmissionWarning != null) {
      _addBotMessage(result.transmissionWarning!, isResult: false);
    }

    // 太阴少阴交界预警
    if (result.answers['_taiyin_to_shaoyin'] == true) {
      _addBotMessage('太阴→少阴传变预警\n'
          '太阴日久及肾：脉由沉迟转沉微，精神由倦怠转萎靡\n'
          '当从少阴论治，急温回阳', isResult: false);
    }

    // 少阴兼表证提示
    if (result.answers['_shaoyin_with_table'] == true) {
      _addBotMessage('少阴兼表证\n'
          '少阴病始得之，反发热脉沉者——麻黄附子细辛汤\n'
          '温经解表，表里双解', isResult: false);
    }

    // v1.11.8 ④ 六经公式分型速查（主证经 → 分型/脉象/治法/代表方）
    final fam = meridianFormulaFamilyOf(result.meridian);
    if (fam != null) {
      final sb = StringBuffer('六经公式分型（${fam.meridian}）\n'
          '提纲：${fam.tag}\n');
      for (final t in fam.types) {
        sb.writeln('\n• ${t.name}');
        sb.writeln('  症状：${t.sym}');
        sb.writeln('  脉象：${t.pulse} · 治法：${t.treat}');
        sb.writeln('  代表方：${t.rx}');
      }
      sb.writeln('\n辨证要点：${fam.keys}');
      _addBotMessage(sb.toString(), isResult: false);
    }

    // 调护建议
    if (result.careAdvice != null) {
      String careText = '调护建议\n';
      for (final entry in result.careAdvice!.entries) {
        careText += '\n【${entry.key}】';
        for (final item in entry.value) {
          careText += '\n• $item';
        }
      }
      _addBotMessage(careText, isResult: false);
    }
    } // end if (isDetailed)

    // P1-1: 简单模式也展示其他可能方剂（详细模式已在鉴别诊断中涵盖）
    if (!isDetailed && result.differential != null) {
      final diff = result.differential!;
      _addBotMessage(
        '其他可能：${diff.name2}（${diff.formula2}）\n'
        '与本案关键区别：${diff.keyDifference}',
        isResult: true,
        diagnosisResult: result,
      );
    }

    _addBotMessage('以上是辨证建议，仅供参考。如需详细查看方剂或药物信息，请点击下方按钮。\n\n'
        '想重新辨证吗？');
    setState(() {
      _currentOptions = [
        _ChatOption(
          label: '重新辨证',
          icon: Icons.refresh,
          onTap: _resetDiagnosis,
        ),
        _ChatOption(
          label: '查看${result.meridian}经详情',
          icon: Icons.menu_book,
          onTap: () => _openMeridianDetail(result.meridian),
        ),
        if (formula != null)
          _ChatOption(
            label: '查看${formula.name}详情',
            icon: Icons.medication,
            onTap: () => _openFormulaDetail(formula),
          ),
        if (!isDetailed && result.differential != null)
          _ChatOption(
            label: '查看${result.differential!.formula2}详情',
            icon: Icons.manage_search,
            onTap: () {
              final alt = FormulaRepository.getByName(result.differential!.formula2);
              if (alt != null) _openFormulaDetail(alt);
            },
          ),
        if (widget.returnResultOnComplete)
          _ChatOption(
            label: '返回 AI 助手',
            icon: Icons.reply,
            onTap: _returnDiagnosisToAssistant,
          ),
        _ChatOption(
          label: '分享辨证结果',
          icon: Icons.share,
          onTap: () => _shareResult(result),
        ),
        if (result.prescription != null)
          _ChatOption(
            label: '复制处方',
            icon: Icons.content_paste,
            onTap: () => _copyPrescription(result.prescription!),
          ),
      ];
      _showOptions = true;
    });
  }

  void _resetDiagnosis() {
    _engine.reset();
    _zhenJiaSelected.clear();
    _pendingPromptId = null;
    _pendingPromptText = null;
    _stepHistory.clear();
    _canGoBack = false;
    setState(() {
      _messages.clear();
    });
    _addBotMessage('好的，我们重新开始。');
    _showTemperatureOptions();
  }

  // ==================== 导航 ====================

  void _openFormulaDetail(Formula formula) {
    Navigator.push(
      context,
      FoldAwareMaterialPageRoute(
        sourceContext: context,
        builder: (_) => FormulaDetailScreen(formula: formula),
      ),
    );
  }

  void _openMeridianDetail(String meridian) {
    Navigator.push(
      context,
      FoldAwareMaterialPageRoute(
        sourceContext: context,
        builder: (_) => MeridianDetailScreen(meridian: meridian),
      ),
    );
  }

  // ==================== 消息管理 ====================

  void _addBotMessage(String text,
      {bool isResult = false,
      bool isWarning = false,
      DiagnosisResult? diagnosisResult,
      Widget? extra}) {
    setState(() {
      _messages.add(_ChatBubble(
        text: text,
        isUser: false,
        isResult: isResult,
        isWarning: isWarning,
        diagnosisResult: diagnosisResult,
        extra: extra,
        onBookmark: isResult && diagnosisResult != null
            ? () => _bookmarkResult(diagnosisResult)
            : null,
      ));
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(_ChatBubble(text: text, isUser: true));
      _showOptions = false;
    });
    _scrollToBottom();
  }

  // ==================== 收藏 ====================

  void _bookmarkResult(DiagnosisResult result) async {
    final db = DatabaseHelper.instance;
    final bookmark = Bookmark(
      title: '${result.displayMeridian}病 - ${result.pattern}',
      content: '六经: ${result.displayMeridian}\n'
          '${result.isCombined ? "合病: ${result.meridian}与${result.combinedMeridian}\n" : ""}'
          '证型: ${result.pattern}\n方剂: ${result.formula}\n\n'
          '${result.patternDetail}\n\n${result.explanation}',
      category: '辨证结果',
      source: 'chat_diagnosis',
    );
    await db.insertBookmark(bookmark);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加到收藏')),
      );
    }
  }

  // ==================== 分享 ====================

  void _shareResult(DiagnosisResult result) {
    final formula = FormulaRepository.getByName(result.formula);
    String text = '【汉唐中医辨证结果】\n\n';
    text += '六经：${result.displayMeridian}病\n';
    if (result.isCombined) {
      text += '合病：${result.meridian}与${result.combinedMeridian}同病\n';
    }
    text += '证型：${result.pattern}\n';
    if (result.formula.isNotEmpty) text += '方剂：${result.formula}\n';
    if (formula != null && formula.components.isNotEmpty) {
      text += '组成：${formula.componentsText}\n';
    }
    if (result.tongueCoating != null || result.tongueShape != null || result.pulseType != null) {
      text += '舌脉：';
      if (result.tongueCoating != null) text += '苔${result.tongueCoating} ';
      if (result.tongueShape != null) text += '形${result.tongueShape} ';
      if (result.pulseType != null) text += '脉${result.pulseType}';
      if (result.pulseTypeSecondary != null) text += '兼脉${result.pulseTypeSecondary}';
      text += '\n';
    }
    text += '\n${result.patternDetail}\n\n';
    text += '${result.explanation}\n\n';
    if (result.careAdvice != null) {
      text += '调护建议：\n';
      for (final entry in result.careAdvice!.entries) {
        text += '【${entry.key}】${entry.value.join("、")}\n';
      }
      text += '\n';
    }
    text += '—— 来自「汉唐中医」App';
    Share.share(text);
  }

  void _copyPrescription(FormulaPrescription prescription) {
    final text = prescription.toCopyText();
    Clipboard.setData(ClipboardData(text: text));
    _addBotMessage('处方已复制到剪贴板，可粘贴发送给药房。');
  }


  // ==================== 检测更新 ====================





  // ==================== 滚动 ====================

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ==================== P2-3 自由文本搜索 ====================

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded) _clearSearch();
    });
  }

  void _onSearchChanged(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final results = FormulaRepository.search(q);
    setState(() => _searchResults = results.take(20).toList());
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchResults = []);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== 构建UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.returnResultOnComplete ? '结构化辨证问诊' : '辨证问诊'),
        actions: [
          if (_canGoBack)
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _goBack,
              tooltip: '返回上一步',
            ),
          IconButton(
            icon: Icon(_searchExpanded ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
            tooltip: '搜索方剂',
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'reset') {
                _resetDiagnosis();
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  FoldAwareMaterialPageRoute(sourceContext: context, builder: (_) => const SettingsScreen()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restart_alt),
                  title: Text('重新开始问诊'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('设置'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searchExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索症状 / 方剂，如：往来寒热、小柴胡汤',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final f = _searchResults[index];
                    return ListTile(
                      title: Text(f.name),
                      subtitle: Text(
                        '${f.meridian} · ${f.indication}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        _openFormulaDetail(f);
                        _clearSearch();
                      },
                    );
                  },
                ),
              ),
          ],
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 18),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _messages[index];
              },
            ),
          ),
          if (_showOptions)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 208),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _currentOptions.map((option) {
                      final scheme = Theme.of(context).colorScheme;
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width > 420
                              ? 164
                              : 132,
                          maxWidth: MediaQuery.of(context).size.width - 40,
                        ),
                        child: OutlinedButton(
                          onPressed: option.onTap,
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 11,
                            ),
                            side: BorderSide(color: scheme.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            backgroundColor: scheme.surface,
                            foregroundColor: scheme.onSurface,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (option.number != null) ...[
                                Text(
                                  '${option.number}.',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 7),
                              ] else if (option.icon != null) ...[
                                Icon(option.icon, size: 17, color: scheme.primary),
                                const SizedBox(width: 7),
                              ],
                              Flexible(
                                child: Text(
                                  option.label,
                                  softWrap: true,
                                  style: const TextStyle(
                                    fontSize: AppType.caption,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 气泡组件 ====================

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isResult;
  final bool isWarning;
  final DiagnosisResult? diagnosisResult;
  final VoidCallback? onBookmark;
  final Widget? extra;

  const _ChatBubble({
    required this.text,
    required this.isUser,
    this.isResult = false,
    this.isWarning = false,
    this.diagnosisResult,
    this.onBookmark,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isWarning
                    ? Theme.of(context).colorScheme.errorContainer
                    : isUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                border: isWarning
                    ? Border.all(
                        color: Theme.of(context).colorScheme.error, width: 1.2)
                    : isResult
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                          )
                        : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: AppType.body,
                  height: 1.5,
                  color: isWarning
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : isUser
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (extra != null) ...[
              const SizedBox(height: 8),
              extra!,
            ],
            if (isResult && onBookmark != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.xs),
                child: TextButton.icon(
                  onPressed: onBookmark,
                  icon: const Icon(Icons.bookmark_add, size: 16),
                  label: const Text('收藏'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== 选项模型 ====================

class _ChatOption {
  final String label;
  final String? description;
  final IconData? icon;
  final int? number;
  final VoidCallback onTap;

  _ChatOption({
    required this.label,
    this.description,
    this.icon,
    this.number,
    required this.onTap,
  });
}
