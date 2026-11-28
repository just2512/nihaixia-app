import 'package:flutter/material.dart';

import '../services/ai_trace.dart';
import '../services/ai_trace_runtime.dart';

/// Explicit, process-local TRACE opt-in for debug builds only.
class LocalAiTraceDebugTile extends StatefulWidget {
  const LocalAiTraceDebugTile({
    super.key,
    this.recorder,
  });

  @visibleForTesting
  final AiTraceRecorder? recorder;

  @override
  State<LocalAiTraceDebugTile> createState() => _LocalAiTraceDebugTileState();
}

class _LocalAiTraceDebugTileState extends State<LocalAiTraceDebugTile> {
  AiTraceRecorder get _recorder => widget.recorder ?? AiTraceRuntime.recorder;

  late bool _enabled = _recorder.isEnabled;
  bool _busy = false;

  Future<void> _setEnabled(bool enabled) async {
    if (_busy || enabled == _enabled) return;

    setState(() => _busy = true);
    try {
      if (enabled) {
        _recorder.enable();
      } else {
        // Wait for queued writes before the UI reports TRACE as disabled.
        await _recorder.disableAndFlush();
      }
    } finally {
      if (mounted) {
        setState(() {
          _enabled = _recorder.isEnabled;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.bug_report_outlined),
      title: const Text('本地 AI 调试 TRACE'),
      subtitle: Text(
        _busy
            ? '正在切换；关闭时会先完成已排队的本地写入。'
            : _enabled
                ? '已启用：只记录脱敏流程元数据，最多 500 条、保留 7 天；重启 App 后自动关闭。'
                : '默认关闭。仅当前调试进程启用；不记录聊天正文、模型回复或附件内容。',
      ),
      value: _enabled,
      onChanged: _busy ? null : _setEnabled,
    );
  }
}
