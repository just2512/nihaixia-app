import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/ziwei_reference_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/adaptive_content_width.dart';

void main() {
  testWidgets('紫微斗数参考页渲染十四主星/十二宫/倪师论命理', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, extensions: [AppColors.light]),
        home: const ZiweiReferenceScreen(),
      ),
    );

    // 标题区 + 倪师论命理（首屏可见）
    expect(find.text('紫微斗数参考'), findsOneWidget);
    expect(find.text('倪师《天纪·天机道》'), findsOneWidget);

    // 十四主星（首屏可见）
    expect(find.text('紫微'), findsOneWidget);
    expect(find.text('天机'), findsOneWidget);
    expect(find.text('土'), findsWidgets); // 五行 tag

    // 滚动到十二宫位区
    await tester.scrollUntilVisible(find.text('十二宫位'), 300);
    expect(find.text('命宫'), findsOneWidget);
    expect(find.text('主管：先天格局、性格'), findsOneWidget);

    // 继续滚动到底部：父母宫
    await tester.scrollUntilVisible(find.text('父母宫'), 300);
    expect(find.text('主管：父母关系'), findsOneWidget);
    expect(find.text('破军'), findsOneWidget);
  });
  testWidgets('展开窗口的紫微参考内容限制宽度并居中', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: [AppColors.light]),
      home: const ZiweiReferenceScreen(),
    ));
    final list = find.byType(ListView).first;
    expect(tester.getSize(find.byType(AdaptiveContentWidth)).width, 1000);
    expect(tester.getSize(list).width, 720);
    expect(tester.getRect(list).center.dx, closeTo(500, 1));
    expect(tester.takeException(), isNull);
  });
}
