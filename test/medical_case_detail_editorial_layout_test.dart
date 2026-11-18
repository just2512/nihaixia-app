import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
import 'package:nihaisha_app/screens/medical_case_detail_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

var _databaseSequence = 0;
late List<MedicalCase> _medicalCases;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _medicalCases = await getAllMedicalCases();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'medical_case_editorial_layout_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  testWidgets(
    '医案详情在402/775dp、浅深主题与200%字号下保持可读和可滚动',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      final medicalCase = _medicalCases.singleWhere((item) => item.seq == 2);

      for (final brightness in Brightness.values) {
        for (final width in [402.0, 775.0]) {
          tester.view.physicalSize = Size(width, 900);
          final tokens =
              brightness == Brightness.dark ? AppColors.dark : AppColors.light;

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(
                'medical-case-${width.toInt()}-${brightness.name}',
              ),
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: AppColors.colorSchemeFor(brightness),
                extensions: [tokens],
                cardTheme: const CardThemeData(elevation: 0),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: MedicalCaseDetailScreen(
                c: medicalCase,
                allCases: _medicalCases,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Flush the serialized recent-history/bookmark work before the next
          // viewport iteration or database teardown.
          final bookmarkState = await tester.runAsync<bool>(
            () => DatabaseHelper.instance.isMedicalCaseBookmarked(
              medicalCase.seq,
            ),
          );
          expect(bookmarkState, isNotNull);
          await tester.pump();

          final pageContext = tester.element(
            find.byType(MedicalCaseDetailScreen),
          );
          expect(
            MediaQuery.textScalerOf(pageContext).scale(1),
            2,
            reason: '医案详情必须实际继承200%系统字号',
          );
          expect(find.text('问 AI 解读当前医案'), findsOneWidget);
          expect(find.text('#${medicalCase.seq}  ${medicalCase.displayName}'), findsOneWidget);

          final bodyList = find.descendant(
            of: find.byType(Scaffold),
            matching: find.byType(ListView),
          ).first;
          expect(
            tester.getSize(bodyList).width,
            lessThanOrEqualTo(width),
            reason: '医案详情列表宽度不得超过当前窗口',
          );
          expect(
            tester.widgetList<Card>(find.byType(Card)).every(
                  (card) => card.elevation == null || card.elevation == 0,
                ),
            isTrue,
            reason: '相关医案卡片必须继承零阴影主题',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 首屏不应溢出',
          );

          await tester.drag(bodyList, const Offset(0, -560));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 连续滚动不应溢出',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    },
  );
}
