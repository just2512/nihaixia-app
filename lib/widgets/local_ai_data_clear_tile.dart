import 'package:flutter/material.dart';

import '../services/local_ai_data_clear_coordinator.dart';

/// Settings entry for deleting only the local-AI data domains currently owned
/// by the app. Legacy shared-temp files and Android backup copies are outside
/// the coordinator's provable deletion boundary and are disclosed explicitly.
class LocalAiDataClearTile extends StatefulWidget {
  const LocalAiDataClearTile({super.key, this.coordinator});

  @visibleForTesting
  final LocalAiDataClearCoordinator? coordinator;

  @override
  State<LocalAiDataClearTile> createState() => _LocalAiDataClearTileState();
}

class _LocalAiDataClearTileState extends State<LocalAiDataClearTile> {
  bool _clearing = false;

  Future<void> _confirmAndClear() async {
    if (_clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除本地 AI 数据'),
        content: const SingleChildScrollView(
          child: Text(
            '将清除当前已纳入管理的本地 AI 数据：\n'
            '• AI 助手会话与消息\n'
            '• 结构化问诊任务快照\n'
            '• AI 专属附件目录中的图片和录音\n'
            '• 本地 TRACE 文件与 Native 运行时缓存\n\n'
            '不会删除已安装模型、收藏、诊断历史、用户设置或其他非 AI 业务数据。\n\n'
            '注意：旧版本遗留在共享系统临时目录中的附件、Android 系统备份副本及外部导出副本不在本次可证明清理范围内。此操作不可撤销。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    late final LocalAiDataClearResult result;
    try {
      result = await (widget.coordinator ??
              LocalAiDataClearCoordinator.forApp())
          .clearAll();
    } catch (_) {
      if (!mounted) return;
      setState(() => _clearing = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('本地 AI 数据清理失败'),
          content: const Text('清理流程未能返回结果。请勿认为数据已全部删除；重新进入设置后可再次尝试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _clearing = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.complete ? '清理范围内的数据已处理' : '本地 AI 数据未完整清理',
        ),
        content: SingleChildScrollView(
          child: Text(_resultSummary(result)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _resultSummary(LocalAiDataClearResult result) {
    final modelStatus = switch (result.installedModelRetained) {
      true => '已安装模型：保留',
      false => '已安装模型：未检测到模型文件',
      null => '已安装模型：保留状态未知',
    };
    final lines = <String>[
      result.complete
          ? '当前清理编排覆盖的数据域均已返回成功。'
          : '清理未完整完成，不能据此认为 AI 数据已全部删除。',
      modelStatus,
    ];
    if (result.failedDomains.isNotEmpty) {
      lines.add('未完成的数据域：${result.failedDomains.join('、')}');
    }
    lines.add(
      '请完全退出并重新启动 App，再检查会话和附件是否仍可见。'
      '旧共享临时目录附件、系统备份副本及外部导出副本仍不在本流程的可证明范围内。',
    );
    return lines.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined,
          color: Theme.of(context).colorScheme.error),
      title: const Text('清除本地 AI 数据'),
      subtitle: const Text(
        '删除当前纳入管理的 AI 会话、附件、TRACE 与运行时缓存；保留已安装模型',
      ),
      contentPadding: EdgeInsets.zero,
      trailing: _clearing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      enabled: !_clearing,
      onTap: _clearing ? null : _confirmAndClear,
    );
  }
}
