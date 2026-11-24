import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../data/dream_data.dart';
import '../models/bookmark.dart';
import '../services/ai_context_prompt_builder.dart';
import '../services/ai_context_resolver.dart';
import '../licensing/feature_authorizer_scope.dart';
import '../services/context_resolution_gateway.dart';
import '../services/dream_result_context_executor.dart';
import '../utils/fold_aware_routes.dart';
import '../theme/app_colors.dart';
import '../theme/yanji_status_semantics.dart';
import '../widgets/yanji_status_badge.dart';
import '../widgets/contextual_ai_sheet.dart' show showContextualAiSheet;
import 'assistant_tool_router.dart' show AssistantMode;

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
  final ScrollController _resultsScrollController = ScrollController();
  String? _openingDreamEntryId;
  String _query = '';
  String? _category; // null = 全部

  @override
  void dispose() {
    _queryController.dispose();
    _resultsScrollController.dispose();
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
                    key: const ValueKey('dream-results-list'),
                    controller: _resultsScrollController,
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

  Future<void> _askAiAboutEntry(DreamEntry entry) async {
    if (_openingDreamEntryId != null) return;
    setState(() => _openingDreamEntryId = entry.id);
    try {
      // Only the explicitly tapped local entry ID crosses this boundary.
      // Search text and the candidate list are deliberately not included.
      final execution = DreamResultContextExecutor.executeWithSnapshot(
        selectedEntryId: entry.id,
      );
      final snapshot = execution.structuredSnapshot;
      if (!execution.succeeded || snapshot == null) {
        throw StateError('所选本地词条不完整或无法建立唯一快照。');
      }

      final ref = AiContextResolver.buildDreamEntryContextRef(
        structuredSnapshot: snapshot,
      );
      final gateway = ContextResolutionGateway(
        authorizer: FeatureAuthorizerScope.of(context),
      );
      final resolution = await gateway.resolve(
        reference: ref,
        resolver: () => AiContextResolver.resolveDreamEntryToolResult(
          ref: ref,
          structuredSnapshot: snapshot,
        ),
        referenceOf: (resolved) => resolved.ref,
      );
      if (!mounted) return;
      if (!resolution.isResolved || resolution.value == null) {
        throw StateError(
          '本地词条核验失败：${resolution.status.name}',
        );
      }

      await showContextualAiSheet(
        context: context,
        contextRef: ref,
        initialPrompt: AiContextPromptBuilder.buildToolResult(
          ref: ref,
          structuredSnapshot: resolution.value!.structuredSnapshot,
        ),
        initialMode: AssistantMode.metaphysics,
        contextualTitle: '周公解梦 · ${entry.keyword}',
        contextualExplanationOnly: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前词条无法建立情境解读：$error')),
      );
    } finally {
      if (mounted) setState(() => _openingDreamEntryId = null);
    }
  }

  Widget _buildDreamCard(DreamEntry e) {
    final cs = Theme.of(context).colorScheme;
    final status = dreamAuspiciousChipColors(e.auspicious, context.colors);
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
                YanjiStatusBadge(label: e.auspicious, colors: status),
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: ValueKey('ask-dream-ai-${e.id}'),
                onPressed: _openingDreamEntryId == null
                    ? () => _askAiAboutEntry(e)
                    : null,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _openingDreamEntryId == e.id ? '正在核验…' : '问 AI 解读此条',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
