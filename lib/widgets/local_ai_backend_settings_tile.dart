import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_ai_service.dart';

/// User-facing E4B backend preference. The selected preference is persisted by
/// Android and applies immediately when a Native Engine is already running.
class LocalAiBackendSettingsTile extends StatefulWidget {
  const LocalAiBackendSettingsTile({
    super.key,
    this.service,
  });

  final LocalAiService? service;

  @override
  State<LocalAiBackendSettingsTile> createState() =>
      _LocalAiBackendSettingsTileState();
}

class _LocalAiBackendSettingsTileState
    extends State<LocalAiBackendSettingsTile> {
  late final LocalAiService _service = widget.service ?? LocalAiService();

  LocalAiModelStatus? _status;
  bool _loading = true;
  bool _saving = false;
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
        _loading = false;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message ?? '无法读取本地 AI 后端状态';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取本地 AI 后端状态失败：$error';
      });
    }
  }

  Future<void> _selectBackend(String backend) async {
    if (_saving || _loading || _status == null) return;
    final status = _status!;
    final isRetryingSelectedBackend =
        status.preferredBackend == backend &&
        status.ready &&
        status.backend != backend;
    if (status.preferredBackend == backend && !isRetryingSelectedBackend) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final nextStatus = await _service.setBackendPreference(backend);
      if (!mounted) return;
      setState(() {
        _status = nextStatus;
        _saving = false;
      });
    } on PlatformException catch (error) {
      await _refreshAfterSwitchFailure(
        error.message ?? '推理后端切换失败',
      );
    } catch (error) {
      await _refreshAfterSwitchFailure('推理后端切换失败：$error');
    }
  }

  Future<void> _refreshAfterSwitchFailure(String message) async {
    LocalAiModelStatus? status;
    try {
      status = await _service.getStatus();
    } catch (_) {
      // Keep the last known preference visible; the failure is still shown.
    }
    if (!mounted) return;
    setState(() {
      _status = status ?? _status;
      _saving = false;
      _error = '$message。可选择另一后端后重试。';
    });
  }

  String _backendLabel(String backend) {
    switch (backend) {
      case 'gpu':
        return 'GPU';
      case 'cpu':
        return 'CPU';
      default:
        return '未加载';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final preferred = status?.preferredBackend ?? 'gpu';
    final actual = status?.backend ?? 'not_loaded';
    final theme = Theme.of(context);

    String runtimeLabel;
    if (_loading) {
      runtimeLabel = '正在读取后端状态…';
    } else if (status == null) {
      runtimeLabel = '当前实际后端未知';
    } else if (!status.ready) {
      runtimeLabel = status.installed
          ? '所选后端：${_backendLabel(preferred)}；模型尚未加载'
          : '所选后端：${_backendLabel(preferred)}；模型尚未安装';
    } else if (actual == preferred) {
      runtimeLabel = '当前实际运行：${_backendLabel(actual)}';
    } else {
      runtimeLabel =
          '所选偏好：${_backendLabel(preferred)}；当前实际运行：${_backendLabel(actual)}（以 Native 实际值为准）';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'E4B 推理后端',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (_loading || _saving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'GPU 与 CPU 可手动切换。切换运行中的后端会重建模型会话，并恢复已完成的对话轮次。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'gpu',
                label: Text('GPU'),
                icon: Icon(Icons.developer_board),
              ),
              ButtonSegment<String>(
                value: 'cpu',
                label: Text('CPU'),
                icon: Icon(Icons.memory_outlined),
              ),
            ],
            selected: <String>{preferred},
            onSelectionChanged: _loading || _saving || status == null
                ? null
                : (selection) => _selectBackend(selection.first),
          ),
          const SizedBox(height: 6),
          Text(runtimeLabel, style: theme.textTheme.bodySmall),
          if (status?.backendFallbackReason != null &&
              status!.backendFallbackReason!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              status.backendFallbackReason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (status != null &&
              status.ready &&
              status.backend != status.preferredBackend) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => _selectBackend(status.preferredBackend),
                icon: const Icon(Icons.refresh),
                label: Text('重新尝试 ${_backendLabel(status.preferredBackend)}'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'GPU 模式沿用现有图形后端配置（语音仍使用 App 当前 CPU 音频后端）；CPU 模式将语言、视觉和音频后端设为 CPU。实际运行状态以 Native 返回值为准。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
