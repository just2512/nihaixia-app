import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';
import '../services/dream_result_context_executor.dart';
import '../services/ai_context_resolver.dart';
import '../services/ai_context_prompt_builder.dart';
import '../screens/assistant_tool_router.dart' show AssistantMode;
import '../widgets/contextual_ai_sheet.dart' show showContextualAiSheet;

import '../data/database_helper.dart';
import '../models/bookmark.dart';
import '../data/dream_data.dart';

/// 周公解梦 —— 《周公解梦大全》结构化数据集民俗占梦查询。
///
/// 支持关键词搜索（关键词/梦境/解读）与分类筛选，逐条渲染梦境卡片，
/// 含吉凶色标。属民俗文化参考，解读为潜意识映射，非吉凶指令。
class DreamScreen extends StatefulWidget {
  const DreamScreen({super.key});

  @override
  State<DreamScreen> createState() => _DreamScreenState();
}

class _DreamScreenState extends State<DreamScreen> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';
  String? _category; // null = 全部
  String? _askingEntryId;

  Future<void> _askAiAboutEntry(DreamEntry entry) async {
    if (_askingEntryId != null) return;
    final execution = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: entry.id,
    );
    if (!execution.succeeded || execution.structuredSnapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选梦境词条无法通过本地数据校验。')),
      );
      return;
    }

    final confirmed = await showFoldAwareDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认解释这条梦境词条'),
        content: Text(
          '将只解释你明确选择的本地词条「${entry.dream}」（ID：${entry.id}）。'
          '不会提交你的自由梦境描述，也不会由 AI 从多个候选中代替选择。'
          '\n\n吉凶标签与释义仅为本地传统民俗文本，不是事实预测或心理、医学结论。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认并解读'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _askingEntryId = entry.id);
    try {
      final contextRef = AiContextResolver.buildDreamEntryResultContextRef(
        structuredSnapshot: execution.structuredSnapshot!,
      );
      final resolution = await AiContextResolver.resolveDreamEntryToolResult(
        ref: contextRef,
        structuredSnapshot: execution.structuredSnapshot!,
      );
      final resolved = resolution.value;
      if (!mounted) return;
      if (!resolution.isResolved || resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('梦境词条核验失败：${resolution.status.name}')),
        );
        return;
      }
      await showContextualAiSheet(
        context: context,
        contextRef: contextRef,
        initialPrompt: AiContextPromptBuilder.buildDreamEntryToolResult(
          resolvedResult: resolved,
        ),
        initialMode: AssistantMode.metaphysics,
        contextualTitle: '周公解梦：${entry.keyword}',
        contextualExplanationOnly: true,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('梦境词条上下文无法核验，已取消 AI 提问。')),
      );
    } finally {
      if (mounted) setState(() => _askingEntryId = null);
    }
  }

  /// 吉凶等级 → 基准色（绿系吉、蓝灰系平、橙红系凶）。
  Color _auspiciousColor(String level) {
    switch (level) {
      case '大吉':
        return Colors.green;
      case '吉':
        return Colors.teal;
      case '平':
        return Colors.blueGrey;
      case '凶':
        return Colors.orange;
      case '大凶':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  /// 记梦：写入一条「记梦」收藏，自动出现在收藏页（category 动态归类）。
  void _showRecordDream(BuildContext context) {
    final titleC = TextEditingController();
    final bodyC = TextEditingController();
    showModalBottomSheet(
      context: context,
      anchorPoint: foldAwareRouteAnchorPoint(context),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleC,
              decoration: const InputDecoration(labelText: '梦的关键词 / 标题'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyC,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '梦境描述（可选）'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final t = titleC.text.trim();
                if (t.isEmpty) return;
                await DatabaseHelper.instance.insertBookmark(Bookmark(
                  title: t,
                  content: bodyC.text.trim(),
                  category: '记梦',
                  source: '周公解梦·记梦',
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      titleC.dispose();
      bodyC.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = searchDreams(_query, _category);

    return Scaffold(
      appBar: AppBar(
        title: const Text('周公解梦'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '记梦',
            onPressed: () => _showRecordDream(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDisclaimer(cs),
          _buildSearchBar(cs),
          _buildCategoryChips(cs),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      '未找到相关梦境',
                      style:
                          TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: results.map(_buildDreamCard).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: cs.tertiaryContainer,
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kDreamDisclaimer,
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _queryController,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: '搜关键词/梦境/解读，如 太阳、竹子、医院',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _queryController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(ColorScheme cs) {
    final chips = <Widget>[
      _buildFilterChip(cs, '全部', _category == null),
    ];
    for (final c in kDreamCategories) {
      chips.add(_buildFilterChip(cs, c.name, _category == c.name));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: chips),
    );
  }

  Widget _buildFilterChip(ColorScheme cs, String label, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            setState(() => _category = (selected ? null : label == '全部' ? null : label)),
        selectedColor: cs.tertiaryContainer,
        checkmarkColor: cs.onTertiaryContainer,
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? cs.onTertiaryContainer : cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildDreamCard(DreamEntry e) {
    final cs = Theme.of(context).colorScheme;
    final accent = _auspiciousColor(e.auspicious);
    return Card(
      key: ValueKey('dream-entry-${e.id}'),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.keyword,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    e.auspicious,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  backgroundColor: accent.withValues(alpha: 0.18),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(e.dream, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              e.interpretation,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '出处：${e.source}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: ValueKey('dream-ask-ai-${e.id}'),
              onPressed: _askingEntryId == null
                  ? () => _askAiAboutEntry(e)
                  : null,
              icon: _askingEntryId == e.id
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _askingEntryId == e.id ? '正在核验…' : '问 AI 解读此词条',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
