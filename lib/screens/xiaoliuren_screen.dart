import 'package:flutter/material.dart';

import '../data/xiaoliuren_data.dart';
import '../screens/assistant_tool_router.dart';
import '../services/ai_context_prompt_builder.dart';
import '../services/ai_context_resolver.dart';
import '../licensing/feature_authorizer_scope.dart';
import '../services/context_resolution_gateway.dart';
import '../services/xiaoliuren_tool_service.dart';
import '../utils/fold_aware_routes.dart';
import '../widgets/contextual_ai_sheet.dart';

int _shiChenIndexOfHour(int hour) => ((hour.clamp(0, 23) + 1) ~/ 2) % 12;

const _kShiChenNames = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

/// 小六壬（六壬时课）—— 时间起课，月/日/时三宫顺数。
///
/// 属民俗文化参考，非吉凶指令。术内对「月初一落宫」本有口径分歧，
/// 页面双口径并列由使用者自选。
class XiaoliurenScreen extends StatefulWidget {
  const XiaoliurenScreen({super.key, this.returnResultOnComplete = false});

  final bool returnResultOnComplete;

  @override
  State<XiaoliurenScreen> createState() => _XiaoliurenScreenState();
}

class _XiaoliurenScreenState extends State<XiaoliurenScreen> {
  DateTime _date = DateTime.now();
  int _shiChen = _shiChenIndexOfHour(DateTime.now().hour);
  XiaoliurenRule _rule = XiaoliurenRule.common;
  XiaoliurenChart? _chart;
  Map<String, Object?>? _contextSnapshot;
  String? _error;
  final ScrollController _pageScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      anchorPoint: foldAwareRouteAnchorPoint(context),
      initialDate: _date,
      firstDate: DateTime(1920),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _compute();
    }
  }

  /// 使用同一次确定性执行返回页面结果与 AI 上下文快照，避免二次计算漂移。
  void _compute() {
    final arguments = <String, String>{
      'date': _formatDate(_date),
      'hour': '${_kShiChenNames[_shiChen]}时',
      'rule': _rule == XiaoliurenRule.common ? 'common' : 'duoneng',
    };
    try {
      final execution = XiaoliurenToolService.executeWithSnapshot(arguments);
      final chart = execution.chart;
      final snapshot = execution.structuredSnapshot;
      if (!execution.succeeded || chart == null || snapshot == null) {
        setState(() {
          _chart = null;
          _contextSnapshot = null;
          _error = execution.result.values['未执行原因'] ??
              '小六壬起课失败，结果状态 UNKNOWN。';
        });
        return;
      }
      setState(() {
        _chart = chart;
        _contextSnapshot = snapshot;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _chart = null;
        _contextSnapshot = null;
        _error = '小六壬起课异常：$error';
      });
    }
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _askAiAboutCurrentResult() async {
    final snapshot = _contextSnapshot;
    if (snapshot == null || _chart == null) return;
    try {
      final contextRef = AiContextResolver.buildXiaoliurenResultContextRef(
        structuredSnapshot: snapshot,
      );
      final gateway = ContextResolutionGateway(
        authorizer: FeatureAuthorizerScope.of(context),
      );
      final resolution = await gateway.resolve(
        reference: contextRef,
        resolver: () => AiContextResolver.resolveXiaoliurenToolResult(
          ref: contextRef,
          structuredSnapshot: snapshot,
        ),
        referenceOf: (resolved) => resolved.ref,
      );
      final resolved = resolution.value;
      if (!mounted) return;
      if (!resolution.isResolved || resolved == null) {
        _showContextError(resolution.status.name.toUpperCase());
        return;
      }
      await showContextualAiSheet(
        context: context,
        contextRef: contextRef,
        initialPrompt: AiContextPromptBuilder.buildXiaoliurenToolResult(
          resolvedResult: resolved,
        ),
        initialMode: AssistantMode.metaphysics,
        contextualTitle: contextRef.title ?? '小六壬起课结果',
        contextualExplanationOnly: true,
      );
    } catch (_) {
      _showContextError('UNKNOWN');
    }
  }

  void _showContextError(String status) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('小六壬结果上下文校验失败：$status，已取消提问。'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _chart;
    return Scaffold(
      appBar: AppBar(
        title: const Text('小六壬'),
        actions: [
          if (widget.returnResultOnComplete && c != null)
            IconButton(
              tooltip: '返回 AI 助手',
              icon: const Icon(Icons.reply),
              onPressed: () => Navigator.pop(
                context,
                [
                  '小六壬起课结果（${_rule.source}）',
                  '日期：${_date.year}-${_date.month}-${_date.day}；农历：${c.lunarMonth}月${c.lunarDay}日',
                  '时辰：${_kShiChenNames[c.hourNumber - 1]}时',
                  '月宫：${c.month.palace.name}',
                  '日宫：${c.day.palace.name}',
                  '正时主断：${c.hour.palace.name}（${c.hour.palace.deity}主事）',
                  '说明：民俗文化参考，非吉凶指令。',
                ].join('\n'),
              ),
            ),
        ],
      ),
      body: ListView(
        controller: _pageScrollController,
        padding: const EdgeInsets.all(16),
        children: [
          _disclaimer(cs),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          '${_date.year}-${_date.month.toString().padLeft(2, '0')}'
                          '-${_date.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                      DropdownButton<int>(
                        value: _shiChen,
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('${_kShiChenNames[i]}时'),
                          ),
                        ),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _shiChen = v);
                          _compute();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<XiaoliurenRule>(
                    segments: const [
                      ButtonSegment(
                        value: XiaoliurenRule.common,
                        label: Text('通行掌诀'),
                      ),
                      ButtonSegment(
                        value: XiaoliurenRule.duoneng,
                        label: Text('《多能鄙事》'),
                      ),
                    ],
                    selected: {_rule},
                    onSelectionChanged: (s) {
                      setState(() => _rule = s.first);
                      _compute();
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '口径：${_rule.source}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (c != null) ...[
            const SizedBox(height: 12),
            _hitCard(
              cs,
              hit: c.hour,
              role: '正时（主断）',
              highlight: true,
              lunar: '农历${c.lunarMonth}月${c.lunarDay}日 '
                  '${_kShiChenNames[c.hourNumber - 1]}时',
            ),
            const SizedBox(height: 12),
            _hitCard(cs, hit: c.month, role: '月宫', highlight: false),
            const SizedBox(height: 12),
            _hitCard(cs, hit: c.day, role: '日宫', highlight: false),
            const SizedBox(height: 12),
            _palaceStrip(cs, c),
            const SizedBox(height: 12),
            _trace(cs, c),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('xiaoliuren-ask-ai-result'),
              onPressed: _contextSnapshot == null ? null : _askAiAboutCurrentResult,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('问 AI 解读当前小六壬结果'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey('xiaoliuren-execution-error'),
              style: TextStyle(color: cs.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _disclaimer(ColorScheme cs) {
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
              '小六壬时间课。作者与成书年代无可靠版本学证据，仅取可复核的顺数规则。'
              '属民俗文化参考，非吉凶指令。',
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hitCard(
    ColorScheme cs, {
    required XiaoliurenHit hit,
    required String role,
    required bool highlight,
    String? lunar,
  }) {
    final verse = xiaoliurenVerse(hit.palace, _rule);
    return Card(
      elevation: highlight ? 3 : 1,
      color: highlight ? cs.primaryContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role,
                        style: TextStyle(
                            fontSize: 11,
                            color: highlight ? cs.primary : cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            hit.palace.name,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: highlight ? cs.primary : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${hit.palace.deity}主事',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (lunar != null)
                  Text(lunar,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(verse, style: const TextStyle(fontSize: 14, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _palaceStrip(ColorScheme cs, XiaoliurenChart c) {
    final marked = {c.month.index, c.day.index, c.hour.index};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('六宫顺序', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(6, (i) {
            final p = kXiaoliurenPalaceOrder[i];
            final on = marked.contains(i);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: on ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                p.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.bold : FontWeight.normal,
                  color: on ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _trace(ColorScheme cs, XiaoliurenChart c) {
    String row(String label, int steps, XiaoliurenHit hit) =>
        '$label：顺数 $steps 步 → 第 ${hit.index + 1} 宫 ${hit.palace.name}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('推算过程',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '月宫 ${row('', c.lunarMonth - 1, c.month).substring(1)}\n'
            '日宫 ${row('', c.lunarMonth + c.lunarDay - 2 + c.rule.dayStartOffset, c.day).substring(1)}\n'
            '时宫 ${row('', c.lunarMonth + c.lunarDay + c.hourNumber - 3 + c.rule.dayStartOffset, c.hour).substring(1)}',
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}
