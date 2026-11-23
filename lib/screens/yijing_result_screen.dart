import 'package:flutter/material.dart';
import '../models/ai_context_ref.dart';
import '../services/ai_context_prompt_builder.dart';
import '../services/ai_context_resolver.dart';
import '../services/yijing_tool_service.dart';
import '../utils/fold_aware_routes.dart';
import 'assistant_tool_router.dart';
import '../widgets/contextual_ai_sheet.dart';
import '../engine/yijing_engine.dart';
import 'yijing_detail_screen.dart';

/// 解卦结果页：本卦 / 动爻 / 变卦 / 互卦
class YiJingResultScreen extends StatefulWidget {
  final CastResult cast;
  final Map<String, String> executionArguments;
  final bool returnResultOnComplete;

  const YiJingResultScreen({
    super.key,
    required this.cast,
    required this.executionArguments,
    this.returnResultOnComplete = false,
  });

  @override
  State<YiJingResultScreen> createState() => _YiJingResultScreenState();
}

class _YiJingResultScreenState extends State<YiJingResultScreen> {
  final ScrollController _pageScrollController = ScrollController();

  Future<void> _askAiAboutResult() async {
    late final Map<String, Object?> snapshot;
    late final AiContextRef contextRef;
    try {
      snapshot = YiJingToolService.createStructuredSnapshot(
        widget.executionArguments,
      );
      if (!YiJingToolService.matchesCast(snapshot: snapshot, cast: widget.cast)) {
        throw StateError('The visible cast does not match the recorded inputs.');
      }
      contextRef = AiContextResolver.buildYiJingResultContextRef(
        structuredSnapshot: snapshot,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('易经结果上下文校验失败：UNKNOWN，已取消提问。'),
          ),
        );
      }
      return;
    }

    final resolution = AiContextResolver.resolveYiJingToolResult(
      ref: contextRef,
      structuredSnapshot: snapshot,
    );
    final resolved = resolution.value;
    if (!resolution.isResolved || resolved == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '易经结果上下文解析失败：${resolution.status.name.toUpperCase()}，已取消提问。',
            ),
          ),
        );
      }
      return;
    }

    await _openContextualAiSheet(
      contextRef: contextRef,
      initialPrompt: AiContextPromptBuilder.buildYiJingToolResult(
        resolvedResult: resolved,
      ),
      contextualTitle: contextRef.title ?? '易经起卦结果',
    );
  }

  Future<void> _askAiAboutField({
    required String fieldPath,
    required String fieldLabel,
  }) async {
    late final Map<String, Object?> snapshot;
    late final AiContextRef resultRef;
    late final AiContextRef fieldRef;
    try {
      snapshot = YiJingToolService.createStructuredSnapshot(
        widget.executionArguments,
      );
      if (!YiJingToolService.matchesCast(snapshot: snapshot, cast: widget.cast)) {
        throw StateError('The visible cast does not match the recorded inputs.');
      }
      resultRef = AiContextResolver.buildYiJingResultContextRef(
        structuredSnapshot: snapshot,
      );
      fieldRef = AiContextResolver.buildYiJingFieldContextRef(
        resultRef: resultRef,
        fieldPath: fieldPath,
        fieldLabel: fieldLabel,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('易经字段上下文校验失败：UNKNOWN，已取消提问。'),
          ),
        );
      }
      return;
    }

    final resolution = AiContextResolver.resolveYiJingResultField(
      ref: fieldRef,
      structuredSnapshot: snapshot,
    );
    final resolved = resolution.value;
    if (!resolution.isResolved || resolved == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '易经字段上下文解析失败：${resolution.status.name.toUpperCase()}，已取消提问。',
            ),
          ),
        );
      }
      return;
    }
    await _openContextualAiSheet(
      contextRef: fieldRef,
      initialPrompt: AiContextPromptBuilder.buildYiJingToolField(
        resolvedField: resolved,
      ),
      contextualTitle: fieldLabel,
    );
  }

  Future<void> _openContextualAiSheet({
    required AiContextRef contextRef,
    required String initialPrompt,
    required String contextualTitle,
  }) async {
    final sourcePageRoute = ModalRoute.of(context);
    final pageScrollOffset = _pageScrollController.hasClients
        ? _pageScrollController.position.pixels
        : null;
    await showContextualAiSheet(
      context: context,
      contextRef: contextRef,
      initialPrompt: initialPrompt,
      initialMode: AssistantMode.tools,
      contextualTitle: contextualTitle,
      contextualExplanationOnly: true,
    );

    var stablePageFrames = 0;
    var pagePositionReady = false;
    for (var frame = 0; frame < 60 && mounted; frame++) {
      final routeIsCurrent =
          sourcePageRoute == null || sourcePageRoute.isCurrent;
      final hasScrollMetrics = _pageScrollController.hasClients &&
          _pageScrollController.position.hasContentDimensions;
      if (routeIsCurrent && hasScrollMetrics) {
        stablePageFrames++;
        if (stablePageFrames >= 18) {
          pagePositionReady = true;
          break;
        }
      } else {
        stablePageFrames = 0;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted ||
        !pagePositionReady ||
        pageScrollOffset == null ||
        !_pageScrollController.hasClients) {
      return;
    }
    final position = _pageScrollController.position;
    final targetOffset = pageScrollOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - targetOffset).abs() > 0.5) {
      _pageScrollController.jumpTo(targetOffset);
    }
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  String _assistantSummary() {
    final buffer = StringBuffer()
      ..writeln('易经起卦结果（${widget.cast.method}）')
      ..writeln('本卦：第${widget.cast.primary.seq}卦 ${widget.cast.primary.name}')
      ..writeln('卦辞：${widget.cast.primary.judgement}')
      ..writeln('动爻：${widget.cast.movingTitles.isEmpty ? '无' : widget.cast.movingTitles.join('、')}')
      ..writeln('爻辞：${widget.cast.movingLines.isEmpty ? widget.cast.movingText : widget.cast.movingTexts.join('；')}');
    if (widget.cast.changed != null) {
      buffer.writeln('变卦：第${widget.cast.changed!.seq}卦 ${widget.cast.changed!.name}；${widget.cast.changed!.judgement}');
    }
    if (widget.cast.nuclear != null) {
      buffer.writeln('互卦：第${widget.cast.nuclear!.seq}卦 ${widget.cast.nuclear!.name}；${widget.cast.nuclear!.judgement}');
    }
    buffer.writeln('说明：民俗文化参考，不是科学预测或确定性结论。');
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('解卦结果'),
        actions: [
          if (widget.executionArguments.isNotEmpty)
            IconButton(
              tooltip: '问 AI 解读当前卦象',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _askAiAboutResult,
            ),
          if (widget.returnResultOnComplete)
            IconButton(
              tooltip: '返回 AI 助手',
              icon: const Icon(Icons.reply),
              onPressed: () => Navigator.pop(context, _assistantSummary()),
            ),
        ],
      ),
      body: ListView(
        controller: _pageScrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(widget.cast.method,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
          // 本卦
          _ResultCard(
            label: '本卦',
            symbol: widget.cast.primarySymbol,
            name: '第${widget.cast.primary.seq}卦 · ${widget.cast.primary.name}',
            body: '「${widget.cast.primary.judgement}」',
            onTap: () => Navigator.push(
              context,
              FoldAwareMaterialPageRoute(sourceContext: context, 
                builder: (_) => YiJingHexagramDetailScreen(
                    hex: widget.cast.primary, highlightLine: widget.cast.moving),
              ),
            ),
          ),
          if (widget.executionArguments.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('yijing-field-primary-name'),
                onPressed: () => _askAiAboutField(
                  fieldPath: 'result.primary.name',
                  fieldLabel: '本卦名称',
                ),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('问 AI 解读本卦名称'),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('yijing-field-primary-judgement'),
                onPressed: () => _askAiAboutField(
                  fieldPath: 'result.primary.judgement',
                  fieldLabel: '本卦卦辞',
                ),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('问 AI 解读本卦卦辞'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 动爻
          Card(
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(widget.cast.movingTitles.join('、'),
                          style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.cast.movingLines.isEmpty) ...[
                    Text('「${widget.cast.movingText}」',
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: colorScheme.onPrimaryContainer)),
                    if (widget.executionArguments.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const ValueKey('yijing-field-moving-0'),
                          onPressed: () => _askAiAboutField(
                            fieldPath: 'result.movingTexts.0',
                            fieldLabel: widget.cast.moving == 0 ? '静卦卦辞' : '${widget.cast.movingTitle}爻辞',
                          ),
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('问 AI 解读当前爻辞/卦辞'),
                        ),
                      ),
                  ] else
                    for (var i = 0; i < widget.cast.movingLines.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      Text(
                        '${widget.cast.movingTitles[i]}：「${widget.cast.movingTexts[i]}」',
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: colorScheme.onPrimaryContainer),
                      ),
                      if (widget.executionArguments.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey('yijing-field-moving-$i'),
                            onPressed: () => _askAiAboutField(
                              fieldPath: 'result.movingTexts.$i',
                              fieldLabel: '${widget.cast.movingTitles[i]}爻辞',
                            ),
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: Text('问 AI 解读${widget.cast.movingTitles[i]}爻辞'),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ),
          if (widget.cast.changed != null) ...[
            const SizedBox(height: 12),
            _ResultCard(
              label: '变卦（${widget.cast.movingLines.isEmpty ? widget.cast.moving : widget.cast.movingLines.length}爻动）',
              symbol: widget.cast.changedSymbol!,
              name: '第${widget.cast.changed!.seq}卦 · ${widget.cast.changed!.name}',
              body: '「${widget.cast.changed!.judgement}」',
              onTap: () => Navigator.push(
                context,
                FoldAwareMaterialPageRoute(sourceContext: context, 
                  builder: (_) => YiJingHexagramDetailScreen(hex: widget.cast.changed!),
                ),
              ),
            ),
            if (widget.executionArguments.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('yijing-field-changed-judgement'),
                  onPressed: () => _askAiAboutField(
                    fieldPath: 'result.changed.judgement',
                    fieldLabel: '变卦卦辞',
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('问 AI 解读变卦卦辞'),
                ),
              ),
          ],
          if (widget.cast.nuclear != null) ...[
            const SizedBox(height: 12),
            _ResultCard(
              label: '互卦',
              symbol: widget.cast.nuclearSymbol!,
              name: '第${widget.cast.nuclear!.seq}卦 · ${widget.cast.nuclear!.name}',
              body: '「${widget.cast.nuclear!.judgement}」',
              onTap: () => Navigator.push(
                context,
                FoldAwareMaterialPageRoute(sourceContext: context, 
                  builder: (_) => YiJingHexagramDetailScreen(hex: widget.cast.nuclear!),
                ),
              ),
            ),
            if (widget.executionArguments.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('yijing-field-nuclear-judgement'),
                  onPressed: () => _askAiAboutField(
                    fieldPath: 'result.nuclear.judgement',
                    fieldLabel: '互卦卦辞',
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('问 AI 解读互卦卦辞'),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            '解卦提示：静卦以卦辞为主断；有动爻以动爻之辞为主断，兼看本卦卦辞与变卦卦辞。'
            '卦辞/爻辞为通行本《周易》原文；人事应用出自倪海厦《天纪·人间道》。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colorScheme.outline, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String symbol;
  final String name;
  final String body;
  final VoidCallback onTap;

  const _ResultCard({
    required this.label,
    required this.symbol,
    required this.name,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(symbol, style: const TextStyle(fontSize: 48)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(body, style: const TextStyle(height: 1.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
