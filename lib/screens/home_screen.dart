import 'package:flutter/material.dart';
import 'local_ai_interview_screen.dart';
import 'knowledge_screen.dart';
import 'bookmarks_screen.dart';
import 'tools_screen.dart';
import 'settings_screen.dart';
import '../services/update_service.dart';
import '../services/whats_new_service.dart';
import '../widgets/update_dialog.dart';
import '../widgets/adaptive_home_navigation.dart';

class HomeScreen extends StatefulWidget {
  final double textScaleFactor;
  final bool runStartupTasks;
  const HomeScreen({
    super.key,
    this.textScaleFactor = 1.0,
    this.runStartupTasks = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.runStartupTasks) return;
    // 启动后弹出「本次更新了什么」（若有版本更新）
    Future.delayed(
      const Duration(milliseconds: 800),
      () {
        if (mounted) WhatsNewService.checkAndShow(context);
      },
    );
    // 延迟检查更新，避免影响启动速度
    Future.delayed(const Duration(seconds: 3), _checkUpdate);
  }

  Future<void> _checkUpdate() async {
    if (!mounted) return;
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;

    if (!context.mounted) return;
    final action = await UpdateDialog.show(context, info);
    if (!mounted || action == null) return;

    switch (action) {
      case UpdateAction.ignore:
        await UpdateService.ignoreVersion(info.version);
      case UpdateAction.permanentlyIgnore:
        await UpdateService.permanentlyIgnoreVersion(info.version);
    }
  }

  final List<Widget> _screens = [
    const LocalAiInterviewScreen(),
    const KnowledgeScreen(),
    const ToolsScreen(),
    const BookmarksScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(widget.textScaleFactor)),
      child: AdaptiveHomeNavigation(
        currentIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        screens: _screens,
        destinations: const [
          AppNavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat),
            label: 'AI助手',
          ),
          AppNavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '知识',
          ),
          AppNavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: '工具',
          ),
          AppNavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: '收藏',
          ),
          AppNavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
