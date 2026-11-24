import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';

import '../data/database_helper.dart';
import '../models/bookmark.dart';
import '../data/yuxiaji_omen_data.dart';

import '../services/yuxiaji_omen_time.dart';
import '../services/ai_context_prompt_builder.dart';
import '../services/ai_context_resolver.dart';
import '../services/context_resolution_gateway.dart';
import '../services/yuxiaji_omen_result_context_executor.dart';
import '../widgets/contextual_ai_sheet.dart';
import 'assistant_tool_router.dart';

/// 玉匣灵兆 —— 《玉匣记》杂占篇·身体兆占。
///
/// 面热/眼跳/耳鸣/心惊等十二时辰占法 + 鸦鸣鹊噪/占灯花特殊占法。
/// 属民俗文化参考，非吉凶指令。
class YuxiajiOmenScreen extends StatefulWidget {
  const YuxiajiOmenScreen({super.key});

  @override
  State<YuxiajiOmenScreen> createState() => _YuxiajiOmenScreenState();
}

class _YuxiajiOmenScreenState extends State<YuxiajiOmenScreen> {
  final DateTime _observedAt = DateTime.now();

  int get _hourIndex => shiChenIndexOf(_observedAt);

  Future<void> _askAiAboutCurrentOmen() async {
    final execution =
        YuxiajiOmenResultContextExecutor.executeWithSnapshot(
      observedAt: _observedAt,
    );
    if (!execution.succeeded || execution.structuredSnapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本次时辰文本未能通过本地来源校验。')),
      );
      return;
    }

    try {
      final contextRef = AiContextResolver.buildYuxiajiOmenResultContextRef(
        structuredSnapshot: execution.structuredSnapshot!,
      );
      const gateway = ContextResolutionGateway();
      final resolution = await gateway.resolve(
        reference: contextRef,
        resolver: () => AiContextResolver.resolveYuxiajiOmenToolResult(
          ref: contextRef,
          structuredSnapshot: execution.structuredSnapshot!,
        ),
        referenceOf: (resolved) => resolved.ref,
      );
      final resolved = resolution.value;
      if (!mounted) return;
      if (!resolution.isResolved || resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('玉匣灵兆结果核验失败：${resolution.status.name}')),
        );
        return;
      }
      await showContextualAiSheet(
        context: context,
        contextRef: contextRef,
        initialPrompt: AiContextPromptBuilder.buildYuxiajiOmenToolResult(
          resolvedResult: resolved,
        ),
        initialMode: AssistantMode.metaphysics,
        contextualTitle: '玉匣灵兆当前时辰文本',
        contextualExplanationOnly: true,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('玉匣灵兆结果无法核验，已取消 AI 提问。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('玉匣灵兆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alert),
            tooltip: '记录身体征兆',
            onPressed: () => _showRecordOmen(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDisclaimer(cs),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                '十二时辰身兆占',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '当前 ${shiChenLabel(_hourIndex)}',
                style: TextStyle(fontSize: 12, color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _askAiAboutCurrentOmen,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('问 AI 解读当前时辰身兆文本'),
          ),
          const SizedBox(height: 8),
          ...kYuXiaJiShiChenOmens.map(_buildOmenCard),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.flare, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              const Text(
                '特殊兆占',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...kYuXiaJiSpecialOmens.map(_buildSpecialCard),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(ColorScheme cs) {
    return Container(
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
              '《玉匣记》杂占篇 · 身体兆占。属民俗文化参考，非吉凶指令。',
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOmenCard(ShiChenOmen omen) {
    final cs = Theme.of(context).colorScheme;
    final current = omen.duanByHour[_hourIndex];
    return Card(
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
                    omen.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  omen.target,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shiChenLabel(_hourIndex),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(current, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '十二时辰详表',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                children: [
                  ...List.generate(12, (i) {
                    final isNow = i == _hourIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 118,
                            child: Text(
                              shiChenLabel(i),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    isNow ? FontWeight.bold : FontWeight.normal,
                                color: isNow ? cs.primary : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              omen.duanByHour[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isNow ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialCard(OmenSpecial s) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              s.target,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            SelectableText(
              s.body,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  /// 身兆记录：写入一条「身兆记录」收藏，source 带入当前时辰。
  void _showRecordOmen(BuildContext context) {
    final nameC = TextEditingController();
    final noteC = TextEditingController();
    final nowLabel = shiChenLabel(_hourIndex);
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
            Text('当前 $nowLabel',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: nameC,
              decoration: const InputDecoration(labelText: '征兆名称（如：左眼跳 / 耳鸣）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteC,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '当时感受 / 备注（可选）'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final n = nameC.text.trim();
                if (n.isEmpty) return;
                await DatabaseHelper.instance.insertBookmark(Bookmark(
                  title: n,
                  content: noteC.text.trim(),
                  category: '身兆记录',
                  source: '玉匣灵兆·$nowLabel',
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      nameC.dispose();
      noteC.dispose();
    });
  }
}
