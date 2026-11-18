import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/yunqi_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/yunqi_tool_executor.dart';

void main() {
  final selectedDate = DateTime(2026, 11, 18);
  const selectedDateText = '2026-11-18';

  test('YunQi snapshot binds selected calendar date and engine version', () {
    final snapshot = YunQiToolExecutor.createStructuredSnapshot(selectedDate);
    final input = snapshot['input']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], 'yunqi');
    expect(snapshot['resultSchemaVersion'], YunQiToolExecutor.resultSchemaVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input['date'], selectedDateText);
    expect(input['yearConvention'], '当前 App 页面采用公历年口径');
    expect(snapshot['ruleVersion'], YunQiToolExecutor.ruleVersion);
    expect(snapshot['sourceIds'], contains(YunQiToolExecutor.sourceId));
    expect(snapshot['snapshotId'], hasLength(64));
    expect(AiToolResultSnapshot.createStructuredId(snapshot: snapshot), snapshot['snapshotId']);

    final otherDate = YunQiToolExecutor.createStructuredSnapshot(DateTime(2027, 1, 2));
    expect(otherDate['snapshotId'], isNot(snapshot['snapshotId']));
  });

  test('YunQi resolver rejects stale versions and mismatched anchors/source', () {
    final snapshot = YunQiToolExecutor.createStructuredSnapshot(selectedDate);
    final ref = AiContextResolver.buildYunqiResultContextRef(structuredSnapshot: snapshot);
    final resolved = AiContextResolver.resolveYunqiToolResult(ref: ref);
    expect(ref.kind, AiContextKind.toolResult);
    expect(ref.moduleId, 'yunqi');
    expect(ref.sourceId, YunQiToolExecutor.sourceId);
    expect(ref.snapshotId, snapshot['snapshotId']);
    expect(resolved.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildYunqiToolResult(resolvedResult: resolved.value!);
    expect(prompt, contains(selectedDateText));
    expect(prompt, contains('公历年'));
    expect(prompt, contains('不得重新排盘、推算'));
    expect(prompt, contains('displaySummary 仅供阅读'));

    final staleRule = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'yunqi-engine@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(AiContextResolver.resolveYunqiToolResult(ref: staleRule).status, AiContextResolutionStatus.stale);

    final changedDateAnchor = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId.replaceFirst(selectedDateText, '2027-01-02'),
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(AiContextResolver.resolveYunqiToolResult(ref: changedDateAnchor).status, AiContextResolutionStatus.unknown);

    const tamperedDigest = '0000000000000000000000000000000000000000000000000000000000000000';
    final tamperedSnapshotRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: 'yunqi:result:$tamperedDigest:date=$selectedDateText',
      anchorVersion: tamperedDigest,
      snapshotId: tamperedDigest,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveYunqiToolResult(ref: tamperedSnapshotRef).status,
      AiContextResolutionStatus.stale,
    );

    final wrongSource = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:yunqi',
      title: ref.title,
    );
    expect(AiContextResolver.resolveYunqiToolResult(ref: wrongSource).status, AiContextResolutionStatus.unknown);

    final wrongTitle = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: '另一个日期的结果',
    );
    expect(AiContextResolver.resolveYunqiToolResult(ref: wrongTitle).status, AiContextResolutionStatus.unknown);
  });

  testWidgets('YunQi result screen exposes contextual Ask AI without auto-opening the panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: YunQiScreen(initialDate: selectedDate)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(YunQiScreen), findsOneWidget);
    expect(find.text('问 AI 解读本年度推算结果'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
