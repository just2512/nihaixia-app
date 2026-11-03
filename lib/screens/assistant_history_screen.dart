import 'package:flutter/material.dart';

import '../data/database_helper.dart';

/// Persistent assistant sessions. Long-press or enter selection mode to
/// delete several conversations; tapping a row resumes that conversation.
class AssistantHistoryScreen extends StatefulWidget {
  const AssistantHistoryScreen({super.key});

  @override
  State<AssistantHistoryScreen> createState() => _AssistantHistoryScreenState();
}

class _AssistantHistoryScreenState extends State<AssistantHistoryScreen> {
  List<Map<String, Object?>> _items = const [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _selectionMode = false;
  bool _deleting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await DatabaseHelper.instance.getAssistantConversations();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      _selected.removeWhere((id) => !_items.any((item) => item['id'] == id));
        if (_selected.isEmpty) _selectionMode = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '无法读取历史对话：$error';
      });
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      _selectionMode = _selected.isNotEmpty || _selectionMode;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除所选对话？'),
        content: Text('将同时删除 ${_selected.length} 个会话及其消息。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await DatabaseHelper.instance.deleteAssistantConversations(_selected.toList());
      _selected.clear();
      _selectionMode = false;
      await _load();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _dateLabel(Object? value) {
    final parsed = DateTime.tryParse(value as String? ?? '');
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selected.length} 个对话' : '历史对话'),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: '删除所选',
              onPressed: _selected.isEmpty || _deleting ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: _selectionMode ? '完成选择' : '批量选择',
            onPressed: _deleting
                ? null
                : () => setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selected.clear();
                    }),
            icon: Icon(_selectionMode ? Icons.done : Icons.checklist),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ))
          : _items.isEmpty
              ? const Center(child: Text('暂无历史对话'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: scheme.outlineVariant),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final id = item['id'] as int;
                      final selected = _selected.contains(id);
                      final title = item['title'] as String? ?? '新对话';
                      final preview = item['last_message_preview'] as String? ?? '';
                      return ListTile(
                        leading: _selectionMode
                            ? Checkbox(
                                value: selected,
                                onChanged: (_) => _toggleSelection(id),
                              )
                            : const CircleAvatar(
                                child: Icon(Icons.chat_bubble_outline),
                              ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          preview.isEmpty ? '暂无消息' : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          _dateLabel(item['updated_at']),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        selected: selected,
                        onLongPress: () {
                          if (!_selectionMode) {
                            setState(() => _selectionMode = true);
                          }
                          _toggleSelection(id);
                        },
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelection(id);
                          } else {
                            Navigator.pop(context, id);
                          }
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
