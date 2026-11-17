import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';

ThemeData _themeFor(Brightness brightness) {
  return ThemeData(
    colorScheme: AppColors.colorSchemeFor(brightness),
    useMaterial3: true,
    extensions: [
      brightness == Brightness.dark ? AppColors.dark : AppColors.light,
    ],
  );
}

Future<void> _pumpYunQi(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  await tester.pumpWidget(
    MaterialApp(
      theme: _themeFor(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: YunQiScreen(initialDate: DateTime.now()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _revealAndCheck(
  WidgetTester tester, {
  required Finder scrollable,
  required Finder target,
  required String segment,
  required double width,
  required Brightness brightness,
}) async {
  // ListView uses lazy children: an off-screen section is not in the
  // widget tree until scrolling reaches it. Scroll first, then assert.
  await tester.scrollUntilVisible(
    target,
    220,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();

  expect(target, findsOneWidget, reason: '$segment 应存在于页面结构中');
  expect(
    tester.takeException(),
    isNull,
    reason: '${width.toInt()}dp / ${brightness.name} / 200%：$segment 不得产生布局异常',
  );

  final targetRect = tester.getRect(target);
  final viewportRect = tester.getRect(scrollable);
  expect(
    targetRect.top,
    greaterThanOrEqualTo(viewportRect.top - 1),
    reason: '$segment 的顶部必须进入实际滚动视口',
  );
  expect(
    targetRect.bottom,
    lessThanOrEqualTo(viewportRect.bottom + 1),
    reason: '$segment 的底部必须进入实际滚动视口',
  );
}

void main() {
  group('五运六气真实视口大字号布局', () {
    testWidgets('402/775dp × 浅深主题 × 200% 下所有分区及图表 Tab 可滚动到达',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetDisplayFeatures);

      for (final brightness in Brightness.values) {
        for (final width in [402.0, 775.0]) {
          await _pumpYunQi(
            tester,
            width: width,
            brightness: brightness,
          );

          final pageContext = tester.element(find.byType(YunQiScreen));
          expect(
            MediaQuery.textScalerOf(pageContext).scale(1),
            2,
            reason: '本场景必须真实使用 200% TextScaler',
          );
          expect(Theme.of(pageContext).brightness, brightness);
          expect(find.text('五运六气推算'), findsOneWidget);

          final scrollable = find
              .descendant(
                of: find.byType(YunQiScreen),
                matching: find.byType(Scrollable),
              )
              .first;

          await _revealAndCheck(
            tester,
            scrollable: scrollable,
            target: find.text('所选日期'),
            segment: '日期选择区',
            width: width,
            brightness: brightness,
          );
          await _revealAndCheck(
            tester,
            scrollable: scrollable,
            target: find.textContaining('运气年 '),
            segment: '年干支总览',
            width: width,
            brightness: brightness,
          );

          await _revealAndCheck(
            tester,
            scrollable: scrollable,
            target: find.text('运气五行图'),
            segment: '三图导航',
            width: width,
            brightness: brightness,
          );
          await tester.tap(find.text('运气五行图'));
          await tester.pumpAndSettle();
          expect(find.byType(WuxingChart), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('五运图'));
          await tester.pumpAndSettle();
          expect(find.byType(WuyunChart), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('六气图'));
          await tester.pumpAndSettle();
          expect(find.byType(LiuqiChart), findsOneWidget);
          expect(tester.takeException(), isNull);

          final sections = <(String, Finder)>[
            ('岁运病候', find.text('岁运（中运）· 病候')),
            ('司天病候', find.text('司天 · 病候')),
            ('司天在泉', find.text('司天 / 在泉')),
            ('内经大论原文', find.text('《内经》大论原文')),
            ('岁运三纪', find.text('岁运三纪 · 胜复郁')),
            ('司天在泉治则病候', find.text('司天在泉 · 治则病候')),
            ('运气格局标签', find.text('运气格局')),
            ('主运五步', find.text('主运五步')),
            ('客运五步', find.text('客运五步')),
            ('主气六步', find.text('主气六步（固定）')),
            ('客气六步', find.text('客气六步')),
            ('今日所处之气', find.text('今日所处之气')),
            ('客主加临表', find.text('客主加临（顺逆）')),
            (
              '底部免责声明',
              find.textContaining('本内容仅供中医理论学习与研究参考'),
            ),
          ];

          for (final (segment, target) in sections) {
            await _revealAndCheck(
              tester,
              scrollable: scrollable,
              target: target,
              segment: segment,
              width: width,
              brightness: brightness,
            );
          }

          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });

    testWidgets('半折叠物理铰链下页面和长内容限制在触发入口所在屏区',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.displayFeatures = [
        DisplayFeature(
          bounds: const Rect.fromLTWH(388, 0, 24, 1000),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      addTearDown(tester.view.resetDisplayFeatures);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: _themeFor(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 412),
                Expanded(
                  child: Builder(
                    builder: (sourceContext) => Center(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sourceContext).push(
                          FoldAwareMaterialPageRoute<void>(
                            sourceContext: sourceContext,
                            builder: (_) => YunQiScreen(
                              initialDate: DateTime.now(),
                            ),
                          ),
                        ),
                        child: const Text('从右侧屏区打开五运六气'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('从右侧屏区打开五运六气'));
      await tester.pumpAndSettle();

      final page = tester.getRect(find.byType(Scaffold).last);
      expect(page.left, greaterThanOrEqualTo(412));
      expect(page.right, lessThanOrEqualTo(800));

      final pageScrollable = find
          .descendant(
            of: find.byType(YunQiScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await _revealAndCheck(
        tester,
        scrollable: pageScrollable,
        target: find.text('客主加临（顺逆）'),
        segment: '半折叠下客主加临表',
        width: 388,
        brightness: Brightness.light,
      );
      await _revealAndCheck(
        tester,
        scrollable: pageScrollable,
        target: find.textContaining('本内容仅供中医理论学习与研究参考'),
        segment: '半折叠下底部免责声明',
        width: 388,
        brightness: Brightness.light,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
