import 'package:flutter/material.dart';

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
            const Text('名称由来与含义', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '“研”取研习、研究之意；“纪”取自倪海厦老师所讲的《天纪》《人纪》《地纪》三纪。'
              '“研纪”就是研习三纪、整理三纪，以三纪为知识脉络，持续学习、梳理和贯通其中的传统知识。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('项目定位与目标', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '研纪是一款以倪师《天纪》《人纪》《地纪》为核心知识脉络的离线优先学习工具。'
              '围绕三纪所涉及的传统知识，整合中医经典与经方、本草、针灸、医案，也涵盖易经、六爻、紫微斗数、八字命理及相关历法、术数和民俗内容。'
              '项目通过资料查阅、知识检索与关联、规则工具、AI 辅助解读、收藏和学习记录等功能，'
              '帮助使用者理解知识内容、梳理不同主题之间的联系、逐步建立系统认识，并持续积累个人研习成果。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '项目希望把分散的典籍资料、知识条目、计算规则和学习过程连接起来：'
              '让资料能够离线查阅、检索和关联，让相关工具能够按明确规则执行，让 AI 帮助理解问题、串联知识、引导追问和解释已经验证的结果，'
              '并通过收藏与记录沉淀个人研习过程。目标是帮助使用者由单点查阅走向体系化理解，而不只是提供资料列表或孤立的计算结果。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('知识内容与功能', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '• 人纪相关：六经辨证与问诊学习、伤寒论、金匮要略、黄帝内经、经方、本草、针灸、倪师医案及专题讲义，帮助学习经典条文、辨病辨证、病机、治法、方剂配伍与针灸思路。\n'
              '• 天纪相关：易经六十四卦、六爻、紫微斗数、八字四柱、命卦等内容，并提供排盘、起卦、结果展示与知识参考。\n'
              '• 其他已整合的传统历法、术数与民俗内容：黄历、节气、五运六气、小六壬、梅花易数、玉匣灵兆、周公解梦、灵签等。\n'
              '天纪、人纪、地纪共同构成研纪的核心知识脉络；以上介绍的是当前应用中已经呈现的内容。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('适用人群', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '• 倪师三纪学习者：希望系统研习《天纪》《人纪》《地纪》，整理知识脉络并进行交叉查阅的人。\n'
              '• 中医与经方研习者：包括中医初学者、自学者、相关专业学生，以及希望研习经典、方剂、本草、针灸和医案的人。\n'
              '• 易学与传统术数爱好者：希望学习易经、六爻、紫微斗数、八字、命卦及相关传统文化内容的人。\n'
              '• 传统文化跨领域学习者：希望把医学、易学、历法与相关传统知识放在整体框架中理解的人。\n'
              '• 个人知识整理者：需要离线查阅、收藏资料、保存命盘或整理长期学习记录的人。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('使用边界', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '研纪以辅助学习为目的，应用内的资料、工具计算和 AI 解读用于帮助使用者理解与研习；'
              '学习者应结合相关知识材料核对内容，并对自己的学习与现实决策保持独立判断。'
              '易经、六爻、紫微斗数、八字及其他术数结果供传统文化研习参考，不代表对现实事件的确定预测。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('研纪更新记录', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '以下仅记录研纪自身版本的功能新增、体验优化与问题修复；当前安装包版本以页面顶部显示为准。',
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text('暂无更新记录', style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12))
            else
              ...entries.map((e) => _buildChangelogEntry(context, e)),
            const SizedBox(height: 16),
            const Text('开源致谢', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '感谢倪海厦老师的经方医学讲授与传承，感谢仲景先师留下《伤寒论》等经典。\n'
              '感谢原始开源项目 jangviktor-web/nihaixia-app 的作者，感谢 ziwei_core、Flutter / Dart 生态中的开源项目作者，以及所有社区贡献者。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
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

