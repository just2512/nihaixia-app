import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

import '../utils/fold_aware_routes.dart';
import '../widgets/adaptive_master_detail.dart';
import '../widgets/state_view.dart';
import 'package:flutter/services.dart';
import '../models/bookmark.dart';
import '../data/database_helper.dart';
import '../data/formula_repository.dart';
import '../data/herb_repository.dart';
import '../data/acupoint_repository.dart';
import '../screens/formula_detail_screen.dart';
import '../screens/herb_detail_screen.dart';
import '../screens/acupoint_detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  @visibleForTesting
  final ValueChanged<List<Bookmark>>? onDataLoaded;

  const BookmarksScreen({super.key, this.onDataLoaded});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

/// 「新建文件夹」弹窗。
///
/// [TextEditingController] 由本 State 持有，并在 [State.dispose] 中销毁——
/// 该 dispose 晚于路由退场动画，避免退场期间（如软键盘收起触发重建）误用已销毁的 controller。
class _CreateFolderDialog extends StatefulWidget {
  /// 文件夹创建成功后回调（宿主据此刷新列表）。
  final VoidCallback onCreated;

  const _CreateFolderDialog({required this.onCreated});

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _submitting) return;
    _submitting = true;
    final nav = Navigator.of(context);
    try {
      await DatabaseHelper.instance.insertFolder(name);
    } catch (e, st) {
      // 捕获而非外抛：onPressed: _submit 未 await，异常外逃会成为「未捕获异步报错」。
      debugPrint('[Bookmarks] 新建文件夹失败：$e\n$st');
    } finally {
      // 无论成功或异常都关闭弹窗，避免失败时弹窗卡死无法操作。
      if (mounted) {
        nav.pop();
        widget.onCreated();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建文件夹'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: '输入文件夹名称',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Bookmark> _bookmarks = [];
  List<Map<String, dynamic>> _folders = [];
  String? _selectedCategory;
  int? _selectedFolderId;
  int? _selectedBookmarkId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.bookmarkVersion.addListener(_onBookmarkChanged);
    _loadData();
  }

  @override
  void dispose() {
    DatabaseHelper.bookmarkVersion.removeListener(_onBookmarkChanged);
    super.dispose();
  }

  void _onBookmarkChanged() {
    if (mounted) _loadData();
  }

  void _loadData() async {
    final generation = ++_loadGeneration;
    final db = DatabaseHelper.instance;
    final folders = await db.getAllFolders();
    List<Bookmark> bookmarks;
    if (_selectedFolderId != null) {
      final rows = await db.getBookmarksWithFolder();
      bookmarks = rows
          .where((r) => r['folder_id'] == _selectedFolderId)
          .map((json) => Bookmark.fromJson(json))
          .toList();
    } else if (_selectedCategory != null) {
      bookmarks = await db.getBookmarksByCategory(_selectedCategory!);
    } else {
      bookmarks = await db.getAllBookmarks();
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _folders = folders;
      _bookmarks = bookmarks;
      if (_selectedBookmarkId != null &&
          !bookmarks.any((bookmark) => bookmark.id == _selectedBookmarkId)) {
        _selectedBookmarkId = null;
      }
    });
    widget.onDataLoaded?.call(bookmarks);
  }

  void _deleteBookmark(int id) async {
    final db = DatabaseHelper.instance;
    await db.deleteBookmark(id);
    _loadData();
  }

  /// 点击收藏项：优先跳转到对应条目的详情页（方剂→方剂介绍页，药物→药物页）。
  /// 若按名称查不到对应条目（如名称变更），则回退为原始文本展示。
  void _openBookmark(Bookmark b) {
    if (b.category == '方剂') {
      final formula = FormulaRepository.getByName(b.title);
      if (formula != null) {
        Navigator.push(
          context,
          FoldAwareMaterialPageRoute(sourceContext: context, builder: (_) => FormulaDetailScreen(formula: formula)),
        );
        return;
      }
    } else if (b.category == '本草') {
      final herb = HerbRepository.getByName(b.title);
      if (herb != null) {
        Navigator.push(
          context,
          FoldAwareMaterialPageRoute(sourceContext: context, builder: (_) => HerbDetailScreen(herb: herb)),
        );
        return;
      }
    } else if (b.category == '穴位') {
      final acupoint = AcupointRepository.findByName(b.title);
      if (acupoint != null) {
        Navigator.push(
          context,
          FoldAwareMaterialPageRoute(
            sourceContext: context,
            builder: (_) => AcupointDetailScreen(acupoint: acupoint),
          ),
        );
        return;
      }
    }
    showFoldAwareDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(b.title),
        content: SingleChildScrollView(child: Text(b.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ==================== 文件夹管理 ====================

  Future<void> _showCreateFolderDialog() async {
    await showFoldAwareDialog(
      context: context,
      builder: (_) => _CreateFolderDialog(onCreated: _loadData),
    );
  }

  void _showDeleteFolderDialog(int folderId, String name) {
    showFoldAwareDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确定删除文件夹「$name」吗？\n文件夹内的收藏将被移出，不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await DatabaseHelper.instance.deleteFolder(folderId);
              nav.pop();
              if (_selectedFolderId == folderId) {
                _selectedFolderId = null;
              }
              _loadData();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showMoveToFolderDialog(Bookmark bookmark) {
    showModalBottomSheet(
      context: context,
      anchorPoint: foldAwareRouteAnchorPoint(context),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('移动到文件夹', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off),
              title: const Text('移出文件夹'),
              onTap: () async {
                final nav = Navigator.of(ctx);
                await DatabaseHelper.instance.moveBookmarkToFolder(bookmark.id!, null);
                nav.pop();
                _loadData();
              },
            ),
            ..._folders.map((f) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(f['name']),
                  onTap: () async {
                    final nav = Navigator.of(ctx);
                    await DatabaseHelper.instance.moveBookmarkToFolder(
                        bookmark.id!, f['id']);
                    nav.pop();
                    _loadData();
                  },
                )),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  // ==================== 导出 ====================

  void _exportBookmarks() async {
    final db = DatabaseHelper.instance;
    final data = await db.exportBookmarks();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏数据已复制到剪贴板（JSON格式）')),
      );
    }
  }

  Widget _buildBookmarkPreviewPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_outline, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            '选择一条收藏',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '在左侧列表选择条目，在这里预览内容',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarkPreview(BuildContext context, Bookmark bookmark) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Chip(
                avatar: Icon(
                  bookmark.category == '方剂'
                      ? Icons.medication
                      : bookmark.category == '本草'
                          ? Icons.eco
                          : bookmark.category == '穴位'
                              ? Icons.spa
                              : Icons.bookmark,
                  size: 16,
                ),
                label: Text(bookmark.category),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                MaterialLocalizations.of(context).formatShortDate(
                  bookmark.createdAt,
                ),
                style: TextStyle(
                  fontSize: AppType.caption,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            bookmark.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            bookmark.source.isEmpty ? '未记录来源' : '来源：${bookmark.source}',
            style: TextStyle(
              fontSize: AppType.caption,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: AppSpacing.xl),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                bookmark.content,
                style: const TextStyle(height: 1.65),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _openBookmark(bookmark),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('打开完整详情'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final categories = _bookmarks.map((b) => b.category).toSet().toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _exportBookmarks();
              if (value == 'new_folder') _showCreateFolderDialog();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_folder',
                child: Row(
                  children: [
                    Icon(Icons.create_new_folder, size: 20),
                    SizedBox(width: 8),
                    Text('新建文件夹'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 8),
                    Text('导出收藏'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 文件夹列表
          if (_folders.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: _selectedFolderId == null,
                      onSelected: (_) {
                        setState(() => _selectedFolderId = null);
                        _loadData();
                      },
                    ),
                    ..._folders.map((f) => Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.sm),
                          child: GestureDetector(
                            onLongPress: () =>
                                _showDeleteFolderDialog(f['id'], f['name']),
                            child: FilterChip(
                              avatar: const Icon(Icons.folder, size: 16),
                              label: Text(f['name']),
                              selected: _selectedFolderId == f['id'],
                              onSelected: (_) {
                                setState(() => _selectedFolderId = f['id']);
                                _loadData();
                              },
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          // 分类标签
          if (categories.isNotEmpty && _selectedFolderId == null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    ...categories.map((cat) => Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: FilterChip(
                            label: Text(cat),
                            selected: _selectedCategory == cat,
                            onSelected: (_) {
                              setState(() {
                                _selectedCategory =
                                    _selectedCategory == cat ? null : cat;
                              });
                              _loadData();
                            },
                          ),
                        )),
                  ],
                ),
              ),
            ),
          // 收藏列表
          Expanded(
            child: _bookmarks.isEmpty
                ? StateView.empty(
                    title: '暂无收藏',
                    hint: '在辨证结果或方剂详情中点击收藏',
                    icon: Icons.bookmark_border,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final useMasterDetail =
                          constraints.maxWidth >= AdaptiveMasterDetail.compactBreakpoint;
                      Bookmark? selectedBookmark;
                      for (final bookmark in _bookmarks) {
                        if (bookmark.id == _selectedBookmarkId) {
                          selectedBookmark = bookmark;
                          break;
                        }
                      }
                      return AdaptiveMasterDetail(
                        master: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          itemCount: _bookmarks.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: AppSpacing.md,
                            indent: 56,
                          ),
                          itemBuilder: (context, index) {
                            final bookmark = _bookmarks[index];
                            final scheme = Theme.of(context).colorScheme;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                child: Icon(
                                  bookmark.category == '方剂'
                                      ? Icons.medication
                                      : bookmark.category == '本草'
                                          ? Icons.eco
                                          : bookmark.category == '穴位'
                                              ? Icons.spa
                                              : Icons.bookmark,
                                  color: scheme.primary,
                                ),
                              ),
                              title: Text(
                                bookmark.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppType.body,
                                ),
                              ),
                              subtitle: Text(
                                bookmark.content.length > 80
                                    ? '${bookmark.content.substring(0, 80)}...'
                                    : bookmark.content,
                                style: const TextStyle(
                                  fontSize: AppType.caption,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    showFoldAwareDialog(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('删除收藏'),
                                        content: const Text('确定删除这条收藏吗？'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              _deleteBookmark(bookmark.id!);
                                              Navigator.pop(dialogContext);
                                            },
                                            child: const Text('删除'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  if (value == 'move') {
                                    _showMoveToFolderDialog(bookmark);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'move',
                                    child: Row(
                                      children: [
                                        Icon(Icons.folder, size: 20),
                                        SizedBox(width: AppSpacing.sm),
                                        Text('移动到文件夹'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 20),
                                        SizedBox(width: AppSpacing.sm),
                                        Text('删除'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              selected:
                                  useMasterDetail &&
                                  bookmark.id == _selectedBookmarkId,
                              selectedTileColor: scheme.primaryContainer,
                              selectedColor: scheme.onPrimaryContainer,
                              onTap: () {
                                if (useMasterDetail) {
                                  setState(
                                    () => _selectedBookmarkId = bookmark.id,
                                  );
                                } else {
                                  _openBookmark(bookmark);
                                }
                              },
                            );
                          },
                        ),
                        detail: selectedBookmark == null
                            ? _buildBookmarkPreviewPlaceholder(context)
                            : _buildBookmarkPreview(context, selectedBookmark),
                        minMasterWidth: 248,
                        maxMasterWidth: 320,
                        masterWidthFactor: 0.4,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
