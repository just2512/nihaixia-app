import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/services/session_state_snapshot_prompt_formatter.dart';

void main() {
  test('preserves provenance and source identity without source body', () {
    final snapshot = SessionStateSnapshot(
      sessionId: 42,
      revision: 'message-19',
      status: SessionStateStatus.restored,
      facts: [
        SessionStateFact(factId: 'user-19', key: 'user_original_message',
          value: '用户原始描述片段', provenance: SessionFactProvenance.userOriginal),
        SessionStateFact(factId: 'confirmed-1', key: 'main_complaint',
          value: '咽部不适', provenance: SessionFactProvenance.userConfirmed,
          sourceIds: const ['user-19']),
        SessionStateFact(factId: 'inferred-1', key: 'possible_pattern',
          value: '模型候选，不是确诊事实',
          provenance: SessionFactProvenance.modelInferred),
      ],
      evidenceReferences: const [
        SessionEvidenceReference(
          sourceId: 'guji:book-1:chapter-2', sourceVersion: 'UNKNOWN',
          evidenceId: 'evidence-7', chunkId: 'chunk-3',
        ),
      ],
    );
    final text = SessionStateSnapshotPromptFormatter.format(
      snapshot, expectedSessionId: 42,
    );
    expect(text, contains('provenance=USER_ORIGINAL'));
    expect(text, contains('provenance=USER_CONFIRMED'));
    expect(text, contains('provenance=MODEL_INFERRED'));
    expect(text, contains('sourceId="guji:book-1:chapter-2"'));
    expect(text, contains('evidenceId="evidence-7"'));
    expect(text, contains('不包含来源正文'));
  });

  test('PARTIAL and omitted messages are not treated as negative facts', () {
    final snapshot = SessionStateSnapshot(
      sessionId: 42, revision: 'message-20',
      status: SessionStateStatus.partial,
      facts: const [], evidenceReferences: const [],
      omittedUserMessageCount: 3,
    );
    final text = SessionStateSnapshotPromptFormatter.format(
      snapshot, expectedSessionId: 42,
    );
    expect(text, contains('status=PARTIAL'));
    expect(text, contains('不能据此断言用户未提及'));
    expect(text, contains('未列出的字段不得被解释为否定或不存在'));
  });

  test('UNKNOWN and SESSION_MISMATCH snapshots never expose facts', () {
    for (final status in [
      SessionStateStatus.unknown,
      SessionStateStatus.sessionMismatch,
    ]) {
      final snapshot = SessionStateSnapshot(
        sessionId: 42, revision: 'UNKNOWN', status: status,
        facts: [
          SessionStateFact(factId: 'must-not-leak', key: 'private',
            value: 'must-not-appear',
            provenance: SessionFactProvenance.userOriginal),
        ],
        evidenceReferences: const [],
      );
      final text = SessionStateSnapshotPromptFormatter.format(
        snapshot, expectedSessionId: 42,
      );
      expect(text, contains('结构化事实：未提供。'));
      expect(text, isNot(contains('must-not-appear')));
      expect(text, isNot(contains('must-not-leak')));
    }
  });

  test('rejects a snapshot owned by another persisted conversation', () {
    final snapshot = SessionStateSnapshot(
      sessionId: 41, revision: 'message-1',
      status: SessionStateStatus.restored,
      facts: const [], evidenceReferences: const [],
    );
    expect(() => SessionStateSnapshotPromptFormatter.format(
      snapshot, expectedSessionId: 42,
    ), throwsArgumentError);
  });

  test('enforces character ceiling and reports omitted whole facts', () {
    final snapshot = SessionStateSnapshot(
      sessionId: 42, revision: 'message-21',
      status: SessionStateStatus.restored,
      facts: List.generate(10, (index) => SessionStateFact(
        factId: 'fact-$index', key: 'large_fact_$index',
        value: List.filled(5000, 'long-value'),
        provenance: SessionFactProvenance.userOriginal,
      )),
      evidenceReferences: const [],
    );
    final text = SessionStateSnapshotPromptFormatter.format(
      snapshot, expectedSessionId: 42,
    );
    expect(text.length, lessThanOrEqualTo(
      SessionStateSnapshotPromptFormatter.maxCharacters,
    ));
    expect(text, contains('快照字符上限导致本轮呈现省略'));
  });
}
