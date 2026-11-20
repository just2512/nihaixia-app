import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';

import '../data/sanshan_lingqian_data.dart';
import '../services/sanshan_lingqian_tool_executor.dart';
import '../services/ai_context_prompt_builder.dart';
import '../services/ai_context_resolver.dart';
import '../services/sanshan_lingqian_result_context_executor.dart';
import '../widgets/contextual_ai_sheet.dart';
import 'assistant_tool_router.dart';

/// 三山国王灵签 —— 广东揭西三山国王祖庙传承 92 签。
///
/// 求签与签谱查阅。属民俗文化参考，非吉凶指令。
class SanshanLingqianScreen extends StatelessWidget {
  const SanshanLingqianScreen({super.key, this.returnResultOnComplete = false});

  final bool returnResultOnComplete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('三山国王灵签'),
          bottom: const TabBar(tabs: [Tab(text: '求签'), Tab(text: '签谱')]),
        ),
        body: Column(
          children: [
            _disclaimer(cs),
            Expanded(
              child: TabBarView(
                children: [
                  _DrawTab(returnResultOnComplete: returnResultOnComplete),
                  const _BrowseTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disclaimer(ColorScheme cs) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '三山国王祖庙（广东揭西）传承 92 签。属潮汕客家地区民间信仰，'
              '民俗文化参考，非吉凶指令。',
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawTab extends StatefulWidget {
  const _DrawTab({this.returnResultOnComplete = false});

  final bool returnResultOnComplete;

  @override
  State<_DrawTab> createState() => _DrawTabState();
}

class _DrawTabState extends State<_DrawTab> {
  LingqianSign? _sign;
  Map<String, Object?>? _structuredSnapshot;

  Future<void> _draw() async {
    final execution =
        await SanshanLingqianResultContextExecutor.drawWithSnapshot();
    if (!mounted) return;
    if (!execution.succeeded || execution.sign == null) {
      setState(() {
        _sign = null;
        _structuredSnapshot = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本次抽签结果未能通过本地签谱校验。')),
      );
      return;
    }
    setState(() {
      _sign = execution.sign;
      _structuredSnapshot = execution.structuredSnapshot;
    });
  }

  Future<void> _askAiAboutResult() async {
    final sign = _sign;
    final snapshot = _structuredSnapshot;
    if (sign == null || snapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先摇签，再解读本次灵签结果。')),
      );
      return;
    }

    try {
      final contextRef = AiContextResolver.buildSanshanLingqianResultContextRef(
        structuredSnapshot: snapshot,
      );
      final resolution =
          await AiContextResolver.resolveSanshanLingqianToolResult(
        ref: contextRef,
        structuredSnapshot: snapshot,
      );
      final resolved = resolution.value;
      if (!mounted) return;
      if (!resolution.isResolved || resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('灵签结果上下文核验失败：${resolution.status.name}')),
        );
        return;
      }

      await showContextualAiSheet(
        context: context,
        contextRef: contextRef,
        initialPrompt: AiContextPromptBuilder.buildToolResult(
          ref: contextRef,
          structuredSnapshot: resolved.structuredSnapshot,
        ),
        initialMode: AssistantMode.metaphysics,
        contextualTitle: '三山国王灵签结果',
        contextualExplanationOnly: true,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('灵签结果无法核验，已取消 AI 提问。')),
      );
    }
  }

  void _returnResultToAssistant() {
    final sign = _sign;
    if (sign == null) return;
    Navigator.pop(context, SanshanLingqianToolExecutor.resultForSign(sign));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _sign;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _draw,
          icon: const Icon(Icons.casino_outlined),
          label: Text(s == null ? '摇签' : '再求一签'),
        ),
        const SizedBox(height: 16),
        if (s == null)
          Text(
            '心默所问之事，然后摇签。',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          )
        else ...[
          _SignCard(sign: s, cs: cs),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _askAiAboutResult,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('问 AI 解读当前灵签结果'),
          ),
          if (widget.returnResultOnComplete) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _returnResultToAssistant,
              icon: const Icon(Icons.reply),
              label: const Text('将本次灵签结果带回助手对话'),
            ),
          ],
        ],
      ],
    );
  }
}

class _BrowseTab extends StatefulWidget {
  const _BrowseTab();

  @override
  State<_BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<_BrowseTab> {
  String _q = '';
  LingqianLuck? _luck;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = kSanShanLingqian.where((s) {
      if (_luck != null && s.luck != _luck) return false;
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return s.title.toLowerCase().contains(q) ||
          s.verse.toLowerCase().contains(q) ||
          s.luck.label.contains(q);
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SearchBar(
            hintText: '搜签题 / 签诗',
            leading: const Icon(Icons.search, size: 20),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('全部'),
                selected: _luck == null,
                onSelected: (_) => setState(() => _luck = null),
              ),
              const SizedBox(width: 6),
              ...LingqianLuck.values.map((l) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(l.label),
                      selected: _luck == l,
                      onSelected: (on) =>
                          setState(() => _luck = on ? l : null),
                    ),
                  )),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text('无匹配签文',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _SignRow(sign: list[i]),
                ),
        ),
      ],
    );
  }
}

/// 签文展示卡（求签结果与签谱详情共用）。
class _SignCard extends StatelessWidget {
  const _SignCard({required this.sign, required this.cs});

  final LingqianSign sign;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _luckColor(sign.luck, cs),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sign.luck.label,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(sign.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                sign.verse,
                style: const TextStyle(fontSize: 15, height: 1.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignRow extends StatelessWidget {
  const _SignRow({required this.sign});

  final LingqianSign sign;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _luckColor(sign.luck, cs),
          child: Text(
            '${sign.id}',
            style: TextStyle(
                fontSize: 12, color: cs.onPrimary, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(sign.title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(sign.luck.label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => showFoldAwareDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            content: SingleChildScrollView(
              child: _SignCard(sign: sign, cs: cs),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _luckColor(LingqianLuck luck, ColorScheme cs) => switch (luck) {
      LingqianLuck.daJi => Colors.green.shade700,
      LingqianLuck.ping => cs.primary,
      LingqianLuck.xiong => Colors.red.shade700,
      LingqianLuck.pingAn => Colors.teal.shade700,
    };
