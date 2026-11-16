import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/fold_aware_routes.dart';

import '../data/guji_data.dart';
import 'markdown_doc_screen.dart';

/// 古籍原文书库：书 → 章节目录（可搜索）→ 章节阅读。
///
/// 定位与「倪海厦讲稿」并列：讲稿是倪师的逐条讲解，这里是经典原文本身。
/// 只收 App 内原本没有的书（灵枢 / 针灸大成），避免内容重复。
class GujiLibraryScreen extends StatelessWidget {
  const GujiLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('古籍原文')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 18, color: cs.onTertiaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '收录《灵枢》《针灸大成》原文。与「倪师讲稿」并列：讲稿是讲解，这里是经典本身。内容供学习参考，非医疗建议。',
                    style: TextStyle(
                      fontSize: AppType.caption,
                      height: 1.5,
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final entry in kGujiBooks.asMap().entries) ...[
            Material(
              color: cs.surface,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.menu_book,
                      size: 20, color: cs.onPrimaryContainer),
                ),
                title: Text(
                  entry.value.title,
                  style: const TextStyle(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${entry.value.author} · ${entry.value.chapterCount} 章',
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                isThreeLine: true,
                onTap: () => Navigator.push(
                  context,
                  FoldAwareMaterialPageRoute(
                    sourceContext: context,
                    builder: (_) => GujiBookScreen(book: entry.value),
                  ),
                ),
              ),
            ),
            if (entry.key < kGujiBooks.length - 1)
              const Divider(height: AppSpacing.lg, indent: 56),
          ],
        ],
      ),
    );
  }
}

/// 单本书的章节目录，支持按章名与正文搜索。
class GujiBookScreen extends StatefulWidget {
  final GujiBook book;

  const GujiBookScreen({super.key, required this.book});

  @override
  State<GujiBookScreen> createState() => _GujiBookScreenState();
}

class _GujiBookScreenState extends State<GujiBookScreen> {
  late Future<List<GujiChapter>> _future;
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = GujiRepository.chaptersOf(widget.book);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<GujiChapter> _filter(List<GujiChapter> all) {
    final q = _query.trim();
    if (q.isEmpty) return all;
    return all
        .where((c) => c.title.contains(q) || c.body.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索本章书名、正文…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<GujiChapter>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('加载失败：${snapshot.error}',
                        style: TextStyle(color: cs.error)),
                  );
                }
                final chapters = _filter(snapshot.data ?? const []);
                if (chapters.isEmpty) {
                  return const Center(child: Text('没有匹配的章节'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  itemCount: chapters.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: AppSpacing.md, indent: 48),
                  itemBuilder: (context, i) {
                    final c = chapters[i];
                    return Material(
                      color: cs.surface,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          FoldAwareMaterialPageRoute(
                            sourceContext: context,
                            builder: (_) => GujiChapterScreen(
                              book: widget.book,
                              chapter: c,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: cs.primaryContainer,
                                child: Text(
                                  '${c.index + 1}',
                                  style: const TextStyle(
                                    fontSize: AppType.micro,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      c.title,
                                      style: const TextStyle(
                                        fontSize: AppType.body,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      c.body.replaceAll('\n', ' '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: AppType.caption,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单章阅读页：正文以 Markdown 渲染，方剂 / 药材名仍可点击跳转。
class GujiChapterScreen extends StatelessWidget {
  final GujiBook book;
  final GujiChapter chapter;

  const GujiChapterScreen({
    super.key,
    required this.book,
    required this.chapter,
  });

  @override
  Widget build(BuildContext context) {
    // 原文按行分段，Markdown 需要空行隔开段落
    final content = chapter.body
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join('\n\n');
    return MarkdownDocScreen(
      title: chapter.title,
      content: content,
      linkFormulas: true,
      footer: '原文出自《${book.title}》（公版古籍），仅供学习参考，非医疗建议。',
    );
  }
}
