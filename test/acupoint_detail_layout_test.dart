import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/zhenjiu_lecture_index.dart';
import 'package:nihaisha_app/models/acupoint_detail.dart';
import 'package:nihaisha_app/screens/acupoint_detail_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

/// 「属性」块布局回归。
///
/// 曾经用 Chip 承载 attribute，Chip 内 Text 不换行，窄屏被裁掉大半
/// （实测 54 字需 761dp，320dp 屏只得 254dp）。这类裁剪**不抛异常**，
/// 只能靠几何断言守：换行后渲染高度必须高于单行。
const String _longAttr =
    '手厥阴心包经络穴，通阴维脉（八脉交会穴）；条文作「手心主之络，别走少阴」，'
    '络脉篇作「别走少阳」，两源并存待考';

const AcupointDetail _p = AcupointDetail(
  name: '内关穴',
  meridian: '手厥阴心包经',
  attribute: _longAttr,
  clinicalNotes: '【倪师主治思路】内关是心包经的络穴，通阴维脉，主心胸胃的病。',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var databaseSequence = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'acupoint_editorial_layout_${databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  testWidgets('穴位详情在402/775dp、浅深主题与200%字号下保持内容可读',
      (tester) async {
    await tester.runAsync(() async {
      try {
        await ZhenJiuLectureIndex.load();
      } catch (_) {}
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('acupoint-${width.toInt()}-${brightness.name}'),
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(brightness),
              extensions: [
                brightness == Brightness.dark ? AppColors.dark : AppColors.light,
              ],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: const AcupointDetailScreen(acupoint: _p),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        final context = tester.element(find.byType(AcupointDetailScreen));
        expect(MediaQuery.textScalerOf(context).scale(1), 2);
        expect(find.text('内关穴'), findsWidgets);
        expect(find.text('古籍原文'), findsOneWidget);
        expect(find.text('倪海厦临床心悟'), findsOneWidget);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(_longAttr),
        );
        expect(paragraph.size.height, greaterThan(30),
            reason: '长属性在200%字号下必须自然换行');
        expect(
          paragraph.size.width,
          lessThanOrEqualTo(width - 32 + 0.5),
          reason: '属性文字不得超出内容列',
        );
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 不应布局溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  testWidgets('320dp + 字号 2.0：54 字属性换行显示、不被裁', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: [AppColors.light]),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: const AcupointDetailScreen(acupoint: _p),
    ));
    await tester.pump();

    final para = tester.renderObject<RenderParagraph>(find.text(_longAttr));
    // 单行高度约 2 倍字高（约 40dp @2.0x）；换行后必然明显更高。
    expect(para.size.height, greaterThan(60),
        reason: '属性未换行——说明又被约束成单行裁掉了');
    expect(para.size.width, lessThanOrEqualTo(320 - 32 + 0.5),
        reason: '属性宽度超出内容区');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
