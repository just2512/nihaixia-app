import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/local_ai_service.dart';

class LocalAiInterviewScreen extends StatefulWidget {
  const LocalAiInterviewScreen({super.key});

  @override
  State<LocalAiInterviewScreen> createState() => _LocalAiInterviewScreenState();
}

class _LocalAiInterviewScreenState extends State<LocalAiInterviewScreen> {
  final LocalAiService _service = LocalAiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_InterviewMessage> _messages = [
    const _InterviewMessage(
      text: '可以先说说目前最困扰你的情况。比如从什么时候开始、具体有什么感觉、什么情况下会加重或缓解。一次说一两件事就可以。',
      isUser: false,
    ),
  ];

  LocalAiModelStatus? _status;
  bool _checking = true;
  bool _loading = false;
  bool _sending = false;
  bool _extracting = false;
  LocalAiSymptomDraft? _confirmedDraft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _checking = false;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = error.message ?? '当前平台尚未接入本地模型运行环境';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '本地 E4B 推理目前仅接入 Android 版本。';
      });
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.loadModel();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
      if (!status.ready) {
        setState(() => _error = '模型文件尚未安装，请先将 Gemma 4 E4B 模型放入应用目录。');
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message ?? '模型加载失败';
      });
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || _status?.ready != true) return;

    _inputController.clear();
    setState(() {
      _messages.add(_InterviewMessage(text: text, isUser: true));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final reply = await _service.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _messages.add(_InterviewMessage(text: reply, isUser: false));
        _sending = false;
      });
      _scrollToBottom();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.message ?? '本地推理失败';
      });
    }
  }

  Future<void> _extractSymptoms() async {
    setState(() {
      _extracting = true;
      _error = null;
    });
    try {
      final draft = await _service.extractSymptoms();
      if (!mounted) return;
      setState(() => _extracting = false);
      if (draft.summaryLines.isEmpty) {
        setState(() => _error = '目前没有提取到明确的自述信息，请补充描述后再整理。');
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var checked = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('核对症状整理'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '以下内容由模型从本次对话中提取。请逐项核对；未提及的信息不会自动补全。',
                      style: TextStyle(fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    ...draft.summaryLines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(line, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (value) =>
                          setDialogState(() => checked = value == true),
                      title: const Text(
                        '我已核对，内容符合我的实际描述',
                        style: TextStyle(fontSize: 13),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('返回修改'),
                ),
                FilledButton(
                  onPressed: checked
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('确认这份整理'),
                ),
              ],
            ),
          );
        },
      );

      if (!mounted || confirmed != true) return;
      setState(() {
        _confirmedDraft = draft;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message ?? '症状整理失败';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message;
      });
    }
  }

  Future<void> _releaseModel() async {
    try {
      final status = await _service.releaseModel();
      if (!mounted) return;
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..add(const _InterviewMessage(
            text: '模型已释放，设备内存已归还。再次使用时可重新加载。',
            isUser: false,
          ));
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? '无法释放模型');
    }
  }

  Future<void> _resetConversation() async {
    try {
      final status = await _service.resetConversation();
      if (!mounted) return;
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..add(const _InterviewMessage(
            text: '我们重新开始。先说说这次最想了解的身体情况。',
            isUser: false,
          ));
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? '无法重置会话');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _status?.ready == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地 AI 问诊'),
        actions: [
          if (ready) ...[
            IconButton(
              tooltip: '重新开始对话',
              onPressed: _sending || _extracting ? null : _resetConversation,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '释放模型内存',
              onPressed: _sending ? null : _releaseModel,
              icon: const Icon(Icons.memory_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildModelPanel(context),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            color: scheme.surfaceContainerLow,
            child: Text(
              'AI 只负责交流和整理自述信息；六经辨证仍由原有规则问诊流程完成，不会由模型开方或调整剂量。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          if (ready && _confirmedDraft == null && _messages.any((m) => m.isUser))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _sending || _extracting ? null : _extractSymptoms,
                  icon: _extracting
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(_extracting ? '正在整理自述…' : '整理本次症状'),
                ),
              ),
            ),
          if (_confirmedDraft != null)
            _buildConfirmedDraftPanel(context),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              itemCount: _messages.length + (_sending || _extracting ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _InterviewMessageBubble(
                    message: _InterviewMessage(
                      text: _extracting ? '正在整理本次对话…' : '正在生成回复…',
                      isUser: false,
                    ),
                  );
                }
                return _InterviewMessageBubble(message: _messages[index]);
              },
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: scheme.errorContainer,
              child: Text(
                _error!,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      enabled: ready && !_sending && !_extracting && _confirmedDraft == null,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: ready ? '描述你的情况…' : '请先安装并加载本地模型',
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: ready && !_sending && !_extracting && _confirmedDraft == null ? _send : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedDraftPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = _confirmedDraft!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已核对的用户自述',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...draft.summaryLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: const TextStyle(fontSize: 12, height: 1.4)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '这份整理不会自动进入辨证引擎，也不会自动选择问诊选项。',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context, draft.summaryLines.join('\\n')),
              child: const Text('返回规则问诊'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_checking) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    final status = _status;
    final ready = status?.ready == true;
    final installed = status?.installed == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.memory : Icons.download_done_outlined,
                size: 18,
                color: ready ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? 'Gemma 4 E4B · ${status!.backend.toUpperCase()}'
                      : installed
                          ? '模型已放入设备，尚未加载'
                          : '等待安装 Gemma 4 E4B 模型',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (ready)
                Text(
                  status!.sizeLabel,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: 7),
            Text(
              installed
                  ? '模型文件：${status!.sizeLabel}'
                  : status?.fileExists == true
                      ? '文件大小不符合当前 E4B 模型包要求（应为 3.66 GB），请重新复制完整文件。'
                      : '模型文件不随 APK 下载或打包，需由用户放入应用私有目录。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 5),
            SelectableText(
              status?.modelPath ?? 'Android 应用私有目录 /files/ai_models/gemma-4-E4B-it.litertlm',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: installed && !_loading ? _loadModel : null,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('加载本地模型'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InterviewMessage {
  final String text;
  final bool isUser;

  const _InterviewMessage({required this.text, required this.isUser});
}

class _InterviewMessageBubble extends StatelessWidget {
  final _InterviewMessage message;

  const _InterviewMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: message.isUser ? scheme.onPrimaryContainer : scheme.onSurface,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}
