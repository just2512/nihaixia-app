import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/knowledge_screen.dart';
import 'package:nihaisha_app/screens/tools_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  group('App capability registry', () {
    test('工具 ID 唯一且每项能力都可从 ID 恢复', () {
      final tools = AssistantToolRouter.all;
      final ids = tools.map((tool) => tool.id).toList(growable: false);
      expect(ids.toSet().length, ids.length);
      for (final tool in tools) {
        expect(tool.id.trim(), isNotEmpty);
        expect(tool.title.trim(), isNotEmpty);
        expect(tool.modes, isNotEmpty, reason: tool.id);
        expect(tool.aliases, isNotEmpty, reason: tool.id);
        expect(tool.actionWords, isNotEmpty, reason: tool.id);
        expect(AssistantToolRouter.byId(tool.id), same(tool));
      }
    });

    test('知识库浏览由统一助手路由到现有知识页面，不复制页面实现', () {
      final tool = AssistantToolRouter.byId('knowledge_hub');
      expect(tool, isNotNull);
      expect(tool!.modes, contains(AssistantMode.learning));
      expect(tool.builder(), isA<KnowledgeScreen>());
    });

    test('学习助手快捷能力不混入纯命理计算器', () {
      final ids = AssistantToolRouter.quickActions(AssistantMode.learning)
          .map((tool) => tool.id)
          .toSet();
      expect(ids, contains('knowledge_hub'));
      expect(ids, contains('guji_library'));
      expect(ids, contains('medical_cases'));
      expect(ids, isNot(contains('ziwei')));
      expect(ids, isNot(contains('bazi')));
    });
  });

  testWidgets('工具页医案数量显示与有效病例记录数一致', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          useMaterial3: true,
          extensions: [AppColors.light],
        ),
        home: const ToolsScreen(),
      ),
    );
    expect(find.textContaining('1256'), findsOneWidget);
    expect(find.textContaining('1113'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
