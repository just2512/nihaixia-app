import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_data_clear_coordinator.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';
import 'package:nihaisha_app/widgets/local_ai_data_clear_tile.dart';

LocalAiRuntimeCacheClearResult _runtimeResult({
  bool released = true,
  bool cacheDeleted = true,
  bool modelExists = true,
}) =>
    LocalAiRuntimeCacheClearResult(
      runtimeReleased: released,
      cacheDeleted: cacheDeleted,
      modelFileExists: modelExists,
    );

LocalAiDataClearCoordinator _coordinator({
  required Future<void> Function() clearAttachments,
}) =>
    LocalAiDataClearCoordinator(
      stopTraceRecording: () async => false,
      resumeTraceRecording: (_) async {},
      clearRuntimeCache: () async => _runtimeResult(),
      clearAttachments: clearAttachments,
      clearTrace: () async {},
      clearDatabase: () async {},
    );

void main() {
  testWidgets('requires confirmation before clearing and reports scoped success',
      (tester) async {
    var attachmentClearCalls = 0;
    final coordinator = _coordinator(
      clearAttachments: () async => attachmentClearCalls++,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: LocalAiDataClearTile(coordinator: coordinator))),
    );

    await tester.tap(find.text('清除本地 AI 数据'));
    await tester.pumpAndSettle();

    expect(find.text('确认清除'), findsOneWidget);
    expect(attachmentClearCalls, 0);
    expect(find.textContaining('旧版本遗留在共享系统临时目录'), findsOneWidget);

    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();

    expect(attachmentClearCalls, 1);
    expect(find.text('清理范围内的数据已处理'), findsOneWidget);
    expect(find.textContaining('已安装模型：保留'), findsOneWidget);
    expect(find.textContaining('完全退出并重新启动 App'), findsOneWidget);
  });

  testWidgets('does not report complete when an owned data domain fails',
      (tester) async {
    final coordinator = _coordinator(
      clearAttachments: () async => throw StateError('injected failure'),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: LocalAiDataClearTile(coordinator: coordinator))),
    );

    await tester.tap(find.text('清除本地 AI 数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();

    expect(find.text('本地 AI 数据未完整清理'), findsOneWidget);
    expect(find.textContaining('attachments'), findsOneWidget);
    expect(find.textContaining('不能据此认为 AI 数据已全部删除'), findsOneWidget);
  });
}
