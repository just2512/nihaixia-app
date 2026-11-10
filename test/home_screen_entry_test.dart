import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // HomeScreen eagerly mounts all tabs. Pre-open the shared FFI database
    // outside widget-test fakeAsync so first-frame tab initialization does
    // not leave sqflite's 10-second transaction synchronization timers pending.
    DatabaseHelper.configureTestDatabase(
      'home_screen_entry_test.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  testWidgets('统一 AI 助手是默认一级入口，设置可从根导航直接进入', (tester) async {
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
      home: const HomeScreen(),
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
    expect(find.text('暗黑模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Find N2 内屏铰链布局下默认 AI 助手不发生布局异常', (tester) async {
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
      home: const HomeScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(IndexedStack), findsOneWidget);
    final contentRect = tester.getRect(find.byType(IndexedStack));
    expect(contentRect.width, lessThanOrEqualTo(388));
    expect(contentRect.right, lessThanOrEqualTo(388));
    expect(find.text('汉唐 AI 助手'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen passes the inherited system text scaler to tab scaffolds', (tester) async {
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
      // Home is a Navigator route. Put the inherited value on the route child
      // itself so the test does not depend on MaterialApp.builder placement.
      home: MediaQuery(
        data: inheritedMediaQuery,
        child: const HomeScreen(),
      ),
    ));
    await tester.pump();

    final homeContext = tester.element(find.byType(HomeScreen));
    final scaffoldContexts = tester.elementList(find.byType(Scaffold));
    expect(MediaQuery.textScalerOf(homeContext).scale(10), 17.5);
    expect(scaffoldContexts, isNotEmpty);
    // Flutter's Material AppBar intentionally clamps title scaling to preserve
    // toolbar hierarchy. Verify the inherited scaler at each screen boundary.
    for (final context in scaffoldContexts) {
      expect(MediaQuery.textScalerOf(context).scale(10), 17.5);
    }
    expect(tester.takeException(), isNull);
  });
}
