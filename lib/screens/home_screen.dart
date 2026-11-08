import 'package:flutter/material.dart';
import 'local_ai_interview_screen.dart';
import 'tools_screen.dart';
import 'knowledge_screen.dart';
import 'bookmarks_screen.dart';
import 'settings_screen.dart';
import '../widgets/adaptive_home_navigation.dart';

class HomeScreen extends StatefulWidget {
  final double textScaleFactor;
  const HomeScreen({
    super.key,
    this.textScaleFactor = 1.0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const LocalAiInterviewScreen(),
    const ToolsScreen(),
    const KnowledgeScreen(),
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
            label: 'AI',
          ),
          AppNavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '工具',
          ),
          AppNavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '知识',
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