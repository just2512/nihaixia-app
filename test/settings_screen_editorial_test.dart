import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/settings_repository.dart';
import 'package:nihaisha_app/screens/settings_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'settings_editorial_${DateTime.now().microsecondsSinceEpoch}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  testWidgets('设置页在402dp与200%字号下不溢出且主题选项持久化',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await SettingsRepository.instance.load();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          extensions: [AppColors.light],
        ),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('深色'));
    await tester.tap(find.text('深色'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });

    expect(SettingsRepository.instance.themeMode, ThemeMode.dark);
    expect(
      await tester.runAsync(
        () => DatabaseHelper.instance.getSetting('theme_mode'),
      ),
      'dark',
    );
    expect(tester.takeException(), isNull);
  });


  testWidgets('设置页在775dp深色主题与200%字号下保持可读', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(775, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await SettingsRepository.instance.load();
      await SettingsRepository.instance.setThemeMode(ThemeMode.dark);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.dark),
          extensions: [AppColors.dark],
        ),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(775, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
