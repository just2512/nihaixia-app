import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/saved_chart_repository.dart';
import 'package:nihaisha_app/screens/saved_charts_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'saved_charts_editorial_${DateTime.now().microsecondsSinceEpoch}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  Future<void> seedCharts() async {
    await SavedChartRepository.insert(
      SavedChart(
        name: '用于验证大字号自然换行的较长命盘名称与家庭备注',
        isMale: true,
        solarIso: DateTime(1990, 6, 15, 8).toIso8601String(),
        lng: 116.41,
        lat: 39.9,
        cityName: '北京市朝阳区一个较长的出生地点名称',
        createdAt: 100,
      ),
    );
    await SavedChartRepository.insert(
      SavedChart(
        name: '短名称命盘',
        isMale: false,
        solarIso: DateTime(1992, 3, 4, 9).toIso8601String(),
        cityName: '上海市',
        createdAt: 200,
      ),
    );
  }

  Future<void> waitForChart(WidgetTester tester, String title) async {
    for (var frame = 0; frame < 40; frame++) {
      if (find.text(title).evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text(title), findsOneWidget,
        reason: '命盘库异步加载后应显示记录');
  }

  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          extensions: [AppColors.light],
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: const TextScaler.linear(2),
          ),
          child: const SavedChartsScreen(),
        ),
      ),
    );
  }

  testWidgets('命盘列表在402/775dp与200%字号下自然换行且保留排盘入口',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(seedCharts);

    const longName = '用于验证大字号自然换行的较长命盘名称与家庭备注';

    for (final width in [402.0, 775.0]) {
      await pumpAtWidth(tester, width);
      await waitForChart(tester, longName);
      expect(find.textContaining('北京市朝阳区一个较长的出生地点名称'), findsOneWidget);
      expect(find.byType(Card), findsNothing,
          reason: '命盘连续列表不应再依赖重复高阴影 Card');
      expect(tester.takeException(), isNull,
          reason: '命盘列表在${width.toInt()}dp与200%字号下不应溢出');

      await tester.tap(find.text(longName));
      await tester.pumpAndSettle();
      expect(find.text('紫微斗数排盘'), findsOneWidget);
      expect(find.text('八字排盘'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: '排盘方式选择弹窗在200%字号下不应溢出');

      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('我的命盘库'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('命盘条目仍可左滑删除并从本地仓储移除', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(seedCharts);
    await pumpAtWidth(tester, 402);

    const longName = '用于验证大字号自然换行的较长命盘名称与家庭备注';
    await waitForChart(tester, longName);
    final dismissible = find.ancestor(
      of: find.text(longName),
      matching: find.byType(Dismissible),
    );
    expect(dismissible, findsOneWidget);
    await tester.ensureVisible(dismissible);
    await tester.drag(dismissible, const Offset(-600, 0));
    await tester.pumpAndSettle();

    List<SavedChart> remaining = const [];
    for (var frame = 0; frame < 20; frame++) {
      remaining = await tester.runAsync(SavedChartRepository.getAll) ?? const [];
      if (remaining.length == 1) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(remaining.map((chart) => chart.name), ['短名称命盘']);
    expect(tester.takeException(), isNull);
  });
}
