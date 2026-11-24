import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/fold_aware_routes.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../data/settings_repository.dart';
import '../data/database_helper.dart';
import '../data/changelog_repository.dart';
import '../services/native_files_stub.dart'
    if (dart.library.io) '../services/native_files_io.dart';
import '../theme/app_colors.dart';
import '../widgets/text_scale_slider.dart';

// ==================== 设置对话框 ====================
// 从 chat_screen.dart 抽离（P2-4）：外观/诊断/数据管理/关于/更新 设置弹窗。

void showSettingsDialog(
  BuildContext context, {
  required VoidCallback onClearHistory,
  required VoidCallback onExportBookmarks,
}) {
  final settings = SettingsRepository.instance;
  showFoldAwareDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === 外观设置 ===
              const Text('外观', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('暗黑模式', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) => settings.setThemeMode(s.first),
              ),
              const SizedBox(height: 16),
              const Text('字体大小', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextScaleSlider(
                value: settings.textScaleFactor,
                onChanged: settings.setTextScaleFactor,
              ),

              const Divider(height: 24),

              // === 诊断设置 ===
              const Text('诊断', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('默认性别'),
                subtitle: Text(settings.defaultGender.isEmpty
                    ? '未设置（每次询问）'
                    : settings.defaultGender == 'male' ? '男' : '女'),
                contentPadding: EdgeInsets.zero,
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '', label: Text('不设置')),
                    ButtonSegment(value: 'male', label: Text('男')),
                    ButtonSegment(value: 'female', label: Text('女')),
                  ],
                  selected: {settings.defaultGender},
                  onSelectionChanged: (s) => settings.setDefaultGender(s.first),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text('诊断详细度'),
                subtitle: Text(settings.diagnosticLevel == 'simple' ? '简单模式' : '详细模式'),
                contentPadding: EdgeInsets.zero,
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'simple', label: Text('简单')),
                    ButtonSegment(value: 'detailed', label: Text('详细')),
                  ],
                  selected: {settings.diagnosticLevel},
                  onSelectionChanged: (s) => settings.setDiagnosticLevel(s.first),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.copy),
                title: const Text('诊断后自动复制处方'),
                subtitle: const Text('诊断完成后自动将处方复制到剪贴板'),
                value: settings.autoCopyPrescription,
                onChanged: (v) => settings.setAutoCopyPrescription(v),
                contentPadding: EdgeInsets.zero,
              ),

              const Divider(height: 24),

              // === 数据管理 ===
              const Text('数据管理', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.history, color: context.colors.warning),
                title: const Text('清除诊断历史'),
                subtitle: const Text('删除所有诊断记录'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  onClearHistory();
                },
              ),
              ListTile(
                leading: Icon(Icons.bookmark, color: context.colors.success),
                title: const Text('导出收藏'),
                subtitle: const Text('将收藏导出为文本'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  onExportBookmarks();
                },
              ),
              ListTile(
                leading: Icon(Icons.cleaning_services, color: context.colors.info),
                title: const Text('清理缓存'),
                subtitle: const Text('清理临时文件释放空间'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  clearAppCache(context);
                },
              ),

              const Divider(height: 24),

              // === 关于 ===
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于'),
                subtitle: const Text('版本信息与致谢'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  showAboutPage(context);
                },
              ),
              const Divider(height: 24),

            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

// ==================== 数据管理（可复用：设置页 / 对话页共用） ====================

void confirmClearHistory(BuildContext context) {
  showFoldAwareDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除诊断历史'),
      content: const Text('确定要删除所有诊断记录吗？此操作不可恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await DatabaseHelper.instance.clearDiagnosisHistory();
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('诊断历史已清除')),
              );
            }
          },
          child: const Text('清除'),
        ),
      ],
    ),
  );
}

Future<void> exportBookmarks(BuildContext context) async {
  final bookmarks = await DatabaseHelper.instance.getAllBookmarks();
  if (!context.mounted) return;

  if (bookmarks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂无收藏')),
    );
    return;
  }

  String text = '【研纪·收藏导出】\n\n';
  for (final b in bookmarks) {
    text += '━━━━━━━━━━━━━━\n';
    text += '${b.title}\n';
    text += '${b.category}\n';
    text += '${b.createdAt}\n\n';
    text += '${b.content}\n\n';
  }
  text += '—— 来自「研纪」App';

  await Share.share(text);
}

// ==================== 清理缓存 ====================

Future<void> clearAppCache(BuildContext context) async {
  try {
    // 临时目录枚举与删除在 clearTempCacheBytes（Web 上恒返回 0）。
    final totalSize = await clearTempCacheBytes();
    if (context.mounted) {
      final sizeMB = (totalSize / 1024 / 1024).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 ${sizeMB}MB 缓存')),
      );
    }
  } catch (e) {
    debugPrint('[AppDialogs] 清理缓存失败：$e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清理缓存失败，请重试')),
      );
    }
  }
}

// ==================== 关于 ====================

Future<void> _copyAboutAddress(
  BuildContext context, {
  required String label,
  required String address,
}) async {
  await Clipboard.setData(ClipboardData(text: address));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$label已复制到剪贴板')),
  );
}

Future<void> showAboutPage(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  await ChangelogRepository.load();
  if (!context.mounted) return;

  final entries = ChangelogRepository.getAll();

  showFoldAwareDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('关于'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(Icons.menu_book_rounded, size: 64,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  const Text('研纪', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('v${info.version}', style: TextStyle(color: context.colors.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text('构建号 ${info.buildNumber}',
                      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('中医诊疗全过程辅助学习软件',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '围绕四诊问诊、信息整理与补问，帮助用户理解辨病、辨证、病机、治法、方剂配伍、针灸取穴，以及经典依据和医案复盘。'
              '辨病辨证结论由 App 既有确定性业务规则执行，并应关联可追溯的本地知识依据；AI 负责理解、引导和解释，不凭自身推断生成或覆盖业务结论。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('功能特色', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '• 六经规则问诊与证候信息整理\n'
              '• 舌象、脉象等问诊参考信息\n'
              '• 经方、本草、穴位与经典资料库\n'
              '• 医案收藏、分享与离线检索\n'
              '• 本地 AI 辅助理解、问诊追问与已验证结果解释（诊断结论由 App 确定性规则产生）\n'
              '• 易经、八字、紫微等传统文化工具（非医疗用途）',
            ),
            const SizedBox(height: 16),
            const Text('项目与版本', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('开发维护：just2512',
                style: TextStyle(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('版本信息读取自当前安装包，不引用上游版本号。',
                style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('本项目仓库', style: TextStyle(fontWeight: FontWeight.w600)),
            const SelectableText('https://github.com/just2512/nihaixia-app'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _copyAboutAddress(
                  context,
                  label: '本项目仓库地址',
                  address: 'https://github.com/just2512/nihaixia-app',
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制本项目地址'),
              ),
            ),
            const Text('上游开源项目', style: TextStyle(fontWeight: FontWeight.w600)),
            const SelectableText('https://github.com/jangviktor-web/nihaixia-app'),
            Text(
              '本仓库保留 GitHub Fork 关系；上游变更按维护策略人工评估、审查和同步。应用版本、更新记录与发行渠道以本仓库为准。',
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _copyAboutAddress(
                  context,
                  label: '上游仓库地址',
                  address: 'https://github.com/jangviktor-web/nihaixia-app',
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制上游地址'),
              ),
            ),
            const Divider(),
            const Text('本仓库更新记录', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '以下为本仓库已登记的更新记录；当前安装包版本以页面顶部显示为准。',
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text('暂无更新记录', style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12))
            else
              ...entries.map((e) => _buildChangelogEntry(context, e)),
            const SizedBox(height: 16),
            const Text('致谢', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('感谢倪海厦老师的经方医学讲授与传承，感谢仲景先师留下《伤寒论》等经典。\n'
                '感谢 jangviktor-web/nihaixia-app 原作者提供原始开源项目与代码基础，也感谢其他开源组件作者和社区贡献者。',
                style: TextStyle(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Center(
              child: Text('© 2026 just2512 · 研纪',
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 关于页中的单条更新日志卡片（最新版本高亮）。
Widget _buildChangelogEntry(BuildContext context, ChangelogEntry e) {
  final isLatest = ChangelogRepository.latest == e;
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: isLatest ? context.colors.infoContainer : context.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isLatest ? context.colors.info : context.colors.outlineVariant,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('v${e.version}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(e.date,
                style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: context.colors.successContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('最近记录',
                    style: TextStyle(color: context.colors.success, fontSize: 10)),
              ),
            ],
          ],
        ),
        if (e.title.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(e.title,
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
        ],
        const SizedBox(height: 6),
        ...e.changes.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $c',
                  style: const TextStyle(fontSize: 12, height: 1.4)),
            )),
      ],
    ),
  );
}

