import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/screens/acupuncture_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AcupunctureRepository.load();
  });

  testWidgets('助手针灸来源按分类 ID 和条目 ID 展开精确处方', (tester) async {
    final category = AcupunctureRepository.getAll().firstWhere(
      (item) => item.id == '01',
    );
    final entry = category.entries.firstWhere((item) => item.id == 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          useMaterial3: true,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: AcupunctureScreen(
            initialCategoryId: category.id,
            initialEntryId: entry.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(entry.symptom), findsWidgets);
    expect(find.text('别名: '), findsOneWidget);
    expect(find.text('关元'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
