import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/home_screen.dart';
import 'package:nihaisha_app/widgets/adaptive_home_navigation.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

List<Widget> _homeShellScreens() => const [
  Scaffold(body: Center(child: Text('汉唐 AI 助手'))),
  Scaffold(body: Center(child: Text('工具测试页'))),
  Scaffold(body: Center(child: Text('知识测试页'))),
  Scaffold(body: Center(child: Text('收藏测试页'))),
  Scaffold(body: Center(child: Text('设置测试页'))),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomeScreen 默认显示 AI 一级入口，设置可从根导航直接进入', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: AppColors.colorSchemeFor(Brightness.light),
        useMaterial3: true,
        extensions: [AppColors.light],
      ),
      home: HomeScreen(testScreens: _homeShellScreens()),
    ));
    await tester.pump();

    expect(find.text('汉唐 AI 助手'), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 0);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('知识'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('设置测试页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Find N2 半折叠根导航将首页限制在物理面板内', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: AppColors.colorSchemeFor(Brightness.light),
        useMaterial3: true,
        extensions: [AppColors.light],
      ),
      home: HomeScreen(testScreens: _homeShellScreens()),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(IndexedStack), findsOneWidget);
    final contentRect = tester.getRect(find.byType(IndexedStack));
    expect(contentRect.width, lessThanOrEqualTo(388));
    expect(contentRect.right, lessThanOrEqualTo(388));
    expect(find.text('汉唐 AI 助手'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdaptiveHomeNavigation 将继承的系统字号传递给各导航页面', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inheritedMediaQuery = MediaQueryData.fromView(
      tester.view,
    ).copyWith(textScaler: const TextScaler.linear(1.75));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: AppColors.colorSchemeFor(Brightness.light),
        useMaterial3: true,
        extensions: [AppColors.light],
      ),
      home: MediaQuery(
        data: inheritedMediaQuery,
        child: AdaptiveHomeNavigation(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          screens: _homeShellScreens(),
          destinations: const [
            AppNavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'AI'),
            AppNavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: '工具'),
            AppNavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '知识'),
            AppNavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: '收藏'),
            AppNavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    ));
    await tester.pump();

    final homeContext = tester.element(find.byType(AdaptiveHomeNavigation));
    final scaffoldContexts = tester.elementList(find.byType(Scaffold));
    expect(MediaQuery.textScalerOf(homeContext).scale(10), 17.5);
    expect(scaffoldContexts, isNotEmpty);
    for (final context in scaffoldContexts) {
      expect(MediaQuery.textScalerOf(context).scale(10), 17.5);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 首页在外屏/内屏、浅深主题与200%字号下保持可读', (tester) async {
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: AppColors.colorSchemeFor(brightness),
            extensions: [brightness == Brightness.dark ? AppColors.dark : AppColors.light],
          ),
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(textScaler: const TextScaler.linear(2)),
            child: HomeScreen(testScreens: _homeShellScreens()),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));

        final homeContext = tester.element(find.byType(HomeScreen));
        expect(MediaQuery.textScalerOf(homeContext).scale(10), 20);
        expect(find.text('汉唐 AI 助手'), findsOneWidget);
        expect(find.byType(IndexedStack), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${width.toInt()}dp / ${brightness.name} / 200% AI 首页不应溢出');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  testWidgets('半折叠 AI 首页在浅深主题与200%字号下避开物理铰链', (tester) async {
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(brightness),
          extensions: [brightness == Brightness.dark ? AppColors.dark : AppColors.light],
        ),
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(textScaler: const TextScaler.linear(2)),
          child: HomeScreen(testScreens: _homeShellScreens()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      final homeContext = tester.element(find.byType(HomeScreen));
      expect(MediaQuery.textScalerOf(homeContext).scale(10), 20);
      final contentRect = tester.getRect(find.byType(IndexedStack));
      expect(contentRect.right, lessThanOrEqualTo(388));
      expect(find.text('汉唐 AI 助手'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${brightness.name} / 半折叠 / 200% AI 首页不应跨越铰链或溢出');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}