import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../models/bookmark.dart';
import '../utils/fold_aware_routes.dart';
import '../models/acupoint_detail.dart';
import '../data/acupoint_repository.dart';
import '../data/database_helper.dart';
import '../data/guji_data.dart';
import '../data/acupuncture_repository.dart';
import '../data/zhenjiu_lecture_index.dart';
import '../models/acupuncture.dart';
import '../theme/app_colors.dart';
import '../models/ai_context_ref.dart';
import '../services/ai_context_resolver.dart';
import '../services/context_resolution_gateway.dart';
import '../services/ai_context_prompt_builder.dart';
import '../services/classic_search_service.dart';
import 'assistant_tool_router.dart' show AssistantMode;
import '../widgets/contextual_ai_sheet.dart' show showContextualAiSheet;
import 'guji_library_screen.dart';
import 'markdown_doc_screen.dart';

/// 临床心悟中解析出的处方公式（如「暖宫方：三毛 + 关元 + 气海 + 三阴交」）。
class _Formula {
  final String title;
  final List<String> points;
  _Formula({required this.title, required this.points});
}

/// 解析临床心悟中的处方公式：
/// - `**XX方**：A + B + C，治…`
/// - `**A透B**…` / `**A配B**…` / `**A配合B**…`
List<_Formula> _parseFormulas(String notes) {
  final formulas = <_Formula>[];
  if (notes.isEmpty) return formulas;
  final pointNames = AcupointRepository.allNames;
  final reg = RegExp(r'\*\*(.+?)\*\*');
  for (final m in reg.allMatches(notes)) {
    final seg = m.group(1)!;
    String scan = seg;
    // 冒号形式（**暖宫方**：A + B…）时，把冒号后的组成一并纳入扫描
    final rest = notes.substring(m.end);
    if (rest.startsWith(RegExp(r'[：:]'))) {
      final endM = RegExp(r'[，。]').firstMatch(rest.substring(1));
      final chunk = endM == null
          ? rest.substring(1)
          : rest.substring(1, endM.start + 1);
      scan = '$seg$chunk';
    }
    final points = _extractPoints(scan, pointNames);
    if (points.isNotEmpty) {
      formulas.add(_Formula(title: seg, points: points));
    }
  }
  return formulas;
}

/// 从文本中按最长优先提取本库穴位名（避免子串误配，如「三阴交」先于「阴交」）。
List<String> _extractPoints(String text, List<String> pointNames) {
  final found = <String>[];
  var s = text;
  for (final name in pointNames) {
    if (s.contains(name)) {
      found.add(name);
      s = s.replaceAll(name, '');
    }
  }
  return found;
}

/// 判断处方/透针中的某个穴名（可能含「透」「、」组合或「穴」后缀）是否命中目标穴。
bool _nameMatches(String container, String target) {
  final t = target.replaceAll('穴', '');
  final parts = container
      .split(RegExp(r'[透、]'))
      .map((e) => e.trim().replaceAll('穴', ''))
      .where((e) => e.isNotEmpty)
      .toList();
  return parts.contains(t);
}

class AcupointDetailScreen extends StatefulWidget {
  final AcupointDetail acupoint;

  const AcupointDetailScreen({super.key, required this.acupoint});

  @override
  State<AcupointDetailScreen> createState() => _AcupointDetailScreenState();
}

class _AcupointDetailScreenState extends State<AcupointDetailScreen> {
  final ScrollController _pageScrollController = ScrollController();
  late List<AcupointDetail> _siblings = _buildSiblings();
  late int _index = _indexOf(widget.acupoint.name);

  int _indexOf(String name) {
    final index = _siblings.indexWhere((item) => item.name == name);
    return index < 0 ? 0 : index;
  }

  List<AcupointDetail> _buildSiblings() {
    final sameMeridian = AcupointRepository.getAll()
        .where((item) => item.meridian == widget.acupoint.meridian)
        .toList();
    if (sameMeridian.isEmpty) return [widget.acupoint];
    if (!sameMeridian.any((item) => item.name == widget.acupoint.name)) {
      sameMeridian.add(widget.acupoint);
    }
    return sameMeridian;
  }


  Future<void> _askAiAboutAcupoint() async {
    final selected = acupoint;
    late final AiContextRef contextRef;
    try {
      contextRef = AiContextResolver.buildAcupointContextRef(
        acupoint: selected,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前穴位无法建立可信的本地知识快照，已取消提问（UNKNOWN）。'),
          ),
        );
      }
      return;
    }

    final gateway = ContextResolutionGateway(
    );
    final resolution = await gateway.resolve<AiResolvedKnowledgeEntry>(
      reference: contextRef,
      resolver: () => AiContextResolver.resolveAcupoint(ref: contextRef),
      referenceOf: (entry) => entry.ref,
    );
    final resolved = resolution.value;
    if (!resolution.isResolved || resolved == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '穴位知识上下文解析失败：${resolution.status.name.toUpperCase()}，已取消提问。',
            ),
          ),
        );
      }
      return;
    }

    final prompt = AiContextPromptBuilder.buildAcupointKnowledgeEntry(
      entry: resolved,
    );
    final sourcePageRoute = ModalRoute.of(context);
    final pageScrollOffset = _pageScrollController.hasClients
        ? _pageScrollController.position.pixels
        : null;
    await showContextualAiSheet(
      context: context,
      contextRef: contextRef,
      initialPrompt: prompt,
      initialMode: AssistantMode.learning,
      contextualTitle: selected.name,
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

  @override
  void didUpdateWidget(covariant AcupointDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.acupoint.name != widget.acupoint.name) {
      _siblings = _buildSiblings();
      _index = _indexOf(widget.acupoint.name);
    }
  }

  AcupointDetail get acupoint => _siblings[_index];

  void _swipe(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _siblings.length) return;
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 关联数据：临床心悟公式 + 反向关联穴位处方/透针
    final formulas = _parseFormulas(acupoint.clinicalNotes);
    final relatedEntries = AcupunctureRepository.getEntries()
        .where((e) => e.acupoints.any((a) => _nameMatches(a.name, acupoint.name)))
        .toList();
    final relatedPens = AcupunctureRepository.getPenetrations()
        .where((p) => _nameMatches(p.name, acupoint.name))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(acupoint.name),
        actions: [
          _AcupointBookmarkButton(
            key: ValueKey(acupoint.name),
            acupoint: acupoint,
          ),
          if (acupoint.meridian.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Chip(
                  label: Text(acupoint.meridian),
                  backgroundColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) _swipe(-1);
          if (velocity < -200) _swipe(1);
        },
        child: ListView(
          key: const ValueKey('acupoint-detail-scroll'),
          controller: _pageScrollController,

          padding: const EdgeInsets.all(16),
          children: [
          if (_siblings.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '第 ${_index + 1}/${_siblings.length} 穴 · 左右滑动切换同经络穴位',
                style: TextStyle(
                  fontSize: AppType.caption,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('acupoint-contextual-ask'),
                onPressed: _askAiAboutAcupoint,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('问 AI 解读当前穴位'),
              ),
            ),
          ),

          // 属性标签
          if (acupoint.attribute.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colors.infoContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(acupoint.attribute),
              ),
            ),

          // 简介
          if (acupoint.description.isNotEmpty)
            _buildSection('简介', acupoint.description, colorScheme, context.colors),

          // 讲义讲解：针灸讲稿中提及本穴的篇目（索引无命中则不显示）
          _buildLectureEntry(colorScheme),

          // 古籍原文：在《针灸大成》《灵枢》中定位本穴相关章节
          _buildGujiEntry(context, colorScheme),

          // 位置
          if (acupoint.location.isNotEmpty)
            _buildSection('位置', acupoint.location, colorScheme, context.colors),

          // 针刺
          if (acupoint.needling.isNotEmpty)
            _buildSection('针刺', acupoint.needling, colorScheme, context.colors),

          // 灸法
          if (acupoint.moxibustion.isNotEmpty)
            _buildSection('灸法', acupoint.moxibustion, colorScheme, context.colors),

          // 禁忌
          if (acupoint.contraindication.isNotEmpty)
            _buildSection('禁忌', acupoint.contraindication, colorScheme, context.colors,
                isWarning: true),

          // 倪海厦临床心悟
          if (acupoint.clinicalNotes.isNotEmpty)
            _buildSection('倪海厦临床心悟', acupoint.clinicalNotes, colorScheme, context.colors,
                isHighlight: true),

          // 倪师处方公式（来自临床心悟）
          if (formulas.isNotEmpty)
            _buildFormulaSection(context, formulas, colorScheme),

          // 关联穴位处方（反向：哪些处方用到此穴）
          if (relatedEntries.isNotEmpty)
            _buildRelatedEntriesSection(context, relatedEntries, colorScheme),

          // 关联透针透穴
          if (relatedPens.isNotEmpty)
            _buildRelatedPenetrationSection(context, relatedPens, colorScheme),
        ],
        ),
      ),
    );
  }

  /// 古籍原文：《针灸大成》《灵枢》中提及本穴的章节入口。
  Widget _buildGujiEntry(BuildContext context, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.auto_stories_outlined, color: colorScheme.primary),
        title: const Text('古籍原文', style: TextStyle(fontSize: AppType.title)),
        subtitle: const Text(
          '《针灸大成》《灵枢》中提及本穴的章节',
          style: TextStyle(fontSize: AppType.caption),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showGujiSheet(context),
      ),
    );
  }

  Future<List<MapEntry<GujiBook, GujiChapter>>> _gujiHits(
      List<String> keys) async {
    final hits = <MapEntry<GujiBook, GujiChapter>>[];
    for (final book in kGujiBooks) {
      for (final chapter in await GujiRepository.chaptersOf(book)) {
        if (keys.any(
          (key) => chapter.title.contains(key) || chapter.body.contains(key),
        )) {
          hits.add(MapEntry(book, chapter));
        }
      }
    }
    return hits;
  }

  void _showGujiSheet(BuildContext context) {
    final key = acupoint.name.replaceAll('穴', '');
    final keys = [key, ...?AcupointRepository.kClassicsAliases[key]];
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: FutureBuilder<List<MapEntry<GujiBook, GujiChapter>>>(
          future: _gujiHits(keys),
          builder: (context, snapshot) {
            final hits = snapshot.data ??
                const <MapEntry<GujiBook, GujiChapter>>[];
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '${acupoint.name} · 古籍提及',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!snapshot.hasData && !snapshot.hasError)
                  const ListTile(title: Text('加载中…')),
                if (snapshot.hasError)
                  ListTile(title: Text('加载失败：${snapshot.error}')),
                if (snapshot.hasData && hits.isEmpty)
                  const ListTile(title: Text('暂无相关章节')),
                for (final hit in hits)
                  ListTile(
                    dense: true,
                    title: Text(hit.value.title,
                        style: const TextStyle(fontSize: AppType.body)),
                    subtitle: Text('《${hit.key.title}》',
                        style: const TextStyle(fontSize: AppType.caption)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        FoldAwareMaterialPageRoute(
                          sourceContext: context,
                          builder: (_) => GujiChapterScreen(
                            book: hit.key,
                            chapter: hit.value,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 讲义讲解：针灸讲稿中提及本穴的篇目入口（索引无命中则不渲染任何内容）。
  Widget _buildLectureEntry(ColorScheme colorScheme) {
    return FutureBuilder<ZhenJiuLectureIndex>(
      future: ZhenJiuLectureIndex.load(),
      builder: (context, snap) {
        final hits = snap.data?.hitsFor(acupoint.name) ?? const [];
        if (hits.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(Icons.menu_book_outlined, color: colorScheme.primary),
            title: const Text('讲义讲解', style: TextStyle(fontSize: AppType.title)),
            subtitle: Text(
              '倪师针灸讲稿中 ${hits.length} 篇提及本穴',
              style: const TextStyle(fontSize: AppType.caption),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLectureSheet(context, hits, colorScheme),
          ),
        );
      },
    );
  }

  void _showLectureSheet(
      BuildContext context, List<LectureHit> hits, ColorScheme colorScheme) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '${acupoint.name} · 讲义提及',
                style: Theme.of(sheetCtx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final h in hits)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    '${h.seq + 1}',
                    style: TextStyle(
                        fontSize: AppType.micro, color: colorScheme.onPrimaryContainer),
                  ),
                ),
                title: Text(
                  ZhenJiuLectureIndex.nameOf(h.seq),
                  style: const TextStyle(fontSize: AppType.body),
                ),
                trailing: Text(
                  '提及 ${h.count} 次',
                  style: TextStyle(
                      fontSize: AppType.caption, color: colorScheme.onSurfaceVariant),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final asset = ZhenJiuLectureIndex.assetOf(h.seq);
                  Navigator.push(
                    context,
                    FoldAwareMaterialPageRoute(sourceContext: context,
                      builder: (_) => MarkdownDocScreen(
                        title: ZhenJiuLectureIndex.nameOf(h.seq),
                        asset: asset,
                        linkFormulas: true,
                        contextualAskModuleId: 'zhenjiu-reading',
                        contextualAskAnchorId:
                            ClassicSearchService.contextualAnchorIdForReaderAsset(
                          moduleId: 'zhenjiu-reading',
                          asset: asset,
                        ),
                        contextualAskSourceId: asset,
                        contextualAskParagraphs: true,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content, ColorScheme colorScheme,
      AppColors colors,
      {bool isWarning = false, bool isHighlight = false}) {
    final bgColor = isWarning
        ? colors.dangerContainer
        : isHighlight
            ? colors.infoContainer
            : colors.surfaceContainerHighest;
    final borderColor = isWarning
        ? colors.danger
        : isHighlight
            ? colors.info
            : colors.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppType.title,
              fontWeight: FontWeight.bold,
              color: isWarning
                  ? colors.danger
                  : isHighlight
                      ? colorScheme.primary
                      : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              content,
              style: const TextStyle(fontSize: AppType.body, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaSection(
      BuildContext context, List<_Formula> formulas, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '倪师处方公式',
            style: TextStyle(
              fontSize: AppType.title,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...formulas.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.infoContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.colors.info),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        f.title,
                        style: TextStyle(
                            fontSize: AppType.caption,
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: f.points
                          .map((p) => _buildPointChip(context, p))
                          .toList(),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRelatedEntriesSection(BuildContext context,
      List<AcupointEntry> entries, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联穴位处方',
            style: TextStyle(
              fontSize: AppType.title,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '以下穴位处方包含本穴',
            style: TextStyle(fontSize: AppType.caption, color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ...entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.symptom,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: e.source == 'nihaisha'
                                  ? context.colors.warningContainer
                                  : context.colors.infoContainer,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              e.sourceLabel,
                              style: TextStyle(
                                fontSize: AppType.micro,
                                color: e.source == 'nihaisha'
                                    ? context.colors.warning
                                    : context.colors.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: e.acupoints
                            .expand((a) => a.name.split(RegExp(r'[透、]')))
                            .map((p) => p.trim())
                            .where((p) => p.isNotEmpty)
                            .map((p) => _buildPointChip(context, p))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRelatedPenetrationSection(BuildContext context,
      List<PenetrationEntry> pens, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联透针透穴',
            style: TextStyle(
              fontSize: AppType.title,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ...pens.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (p.indications.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: p.indications
                              .map((ind) => Chip(
                                    label: Text(ind,
                                        style: const TextStyle(fontSize: AppType.micro)),
                                    backgroundColor: context.colors.successContainer,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: p.name
                            .split(RegExp(r'[透、]'))
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty && s.length <= 4)
                            .map((s) => _buildPointChip(context, s))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  /// 组成穴 chip：可点按跳转详情；未收录则灰显不可点。
  Widget _buildPointChip(BuildContext context, String name) {
    final detail =
        AcupointRepository.findByName(AcupointRepository.canonicalOf(name));
    if (detail == null) {
      return Chip(
        label: Text(name,
            style: TextStyle(fontSize: AppType.caption, color: context.colors.onSurfaceVariant)),
        backgroundColor: context.colors.surfaceContainerHighest,
        visualDensity: VisualDensity.compact,
      );
    }
    final isSelf = detail.name == acupoint.name;
    return GestureDetector(
      onTap: isSelf
          ? null
          : () {
              Navigator.of(context).push(
                FoldAwareMaterialPageRoute(sourceContext: context, 
                  builder: (_) => AcupointDetailScreen(acupoint: detail),
                ),
              );
            },
      child: Chip(
        label: Text(name, style: const TextStyle(fontSize: AppType.caption)),
        backgroundColor: isSelf
            ? context.colors.warningContainer
            : context.colors.infoContainer,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 穴位收藏按钮复用现有 bookmarks 表，不创建第二套收藏存储。
class _AcupointBookmarkButton extends StatefulWidget {
  final AcupointDetail acupoint;
  const _AcupointBookmarkButton({super.key, required this.acupoint});

  @override
  State<_AcupointBookmarkButton> createState() =>
      _AcupointBookmarkButtonState();
}

class _AcupointBookmarkButtonState extends State<_AcupointBookmarkButton> {
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    try {
      final bookmarks =
          await DatabaseHelper.instance.getAllBookmarks();
      final saved = bookmarks.any((bookmark) =>
          bookmark.title == widget.acupoint.name &&
          bookmark.category == '穴位');
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      // 收藏表不可用时不影响穴位详情页。
    }
  }

  Future<void> _toggle() async {
    final database = DatabaseHelper.instance;
    final acupoint = widget.acupoint;
    try {
      if (_saved) {
        final bookmarks = await database.getAllBookmarks();
        for (final bookmark in bookmarks) {
          if (bookmark.title == acupoint.name &&
              bookmark.category == '穴位' &&
              bookmark.id != null) {
            await database.deleteBookmark(bookmark.id!);
            break;
          }
        }
      } else {
        await database.insertBookmark(Bookmark(
          title: acupoint.name,
          content: acupoint.description.isNotEmpty
              ? acupoint.description
              : acupoint.clinicalNotes,
          category: '穴位',
          source: 'acupoint_detail',
        ));
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _saved = !_saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_saved ? '已收藏穴位' : '已取消收藏')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _saved ? '取消收藏' : '收藏穴位',
      icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
      onPressed: _toggle,
    );
  }
}
