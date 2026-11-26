import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
import 'package:nihaisha_app/models/session_state_snapshot.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';
import 'package:nihaisha_app/services/session_state_snapshot_builder.dart';

void main() {
  EngineSnapshot snapshot({
    Map<String, dynamic> answers = const {},
    List<String> selectedSymptoms = const [],
  }) =>
      EngineSnapshot(
        stage: DiagnosticStage.tenQuestions,
        selectedSymptoms: selectedSymptoms,
        answers: answers,
        tenQuestionIndex: 2,
        qAnswers: const {'q1': 2},
      );

  test('SessionStateFact freezes nested JSON values at construction', () {
    final nested = <String, Object?>{
      'answers': <Object?>[
        'original',
        <String, Object?>{'confirmed': true, 'optional': null},
      ],
    };
    final fact = SessionStateFact(
      factId: 'fact:1',
      key: 'structured',
      value: nested,
      provenance: SessionFactProvenance.userConfirmed,
    );

    nested['extra'] = 'late mutation';
    (nested['answers'] as List<Object?>).add('late mutation');

    final value = fact.value as Map<String, Object?>;
    expect(value.containsKey('extra'), isFalse);
    final answers = value['answers'] as List<Object?>;
    expect(answers, hasLength(2));
    expect(() => value['extra'] = 'cannot mutate', throwsUnsupportedError);
    expect(() => answers.add('cannot mutate'), throwsUnsupportedError);
    final answer = answers[1] as Map<String, Object?>;
    expect(() => answer['confirmed'] = false, throwsUnsupportedError);
  });

  test('rejects values that are not JSON-compatible', () {
    SessionStateFact fact(Object value) => SessionStateFact(
          factId: 'fact:invalid',
          key: 'invalid',
          value: value,
          provenance: SessionFactProvenance.userConfirmed,
        );

    expect(() => fact({'value': double.nan}), throwsArgumentError);
    expect(() => fact({'value': double.infinity}), throwsArgumentError);
    expect(() => fact({'value': <int>{1, 2}}), throwsArgumentError);
    expect(() => fact({1: 'non-string key'}), throwsArgumentError);
  });

  test('restores only facts and references belonging to the requested session', () {
    const sessionId = 7;
    final task = TcmInterviewTaskState(
      taskId: 'task-7',
      snapshot: snapshot(
        answers: const {'temperature': 'fever_chills'},
        selectedSymptoms: const ['口苦'],
      ),
      status: 'in_progress',
      pendingConfirmedTenAnswers: const {'sleep': '易醒'},
      updatedAt: DateTime.utc(2026, 11, 25),
    );
    final metadata = AssistantMessageMetadata(
      sourceIds: const ['classic:shanghan:2'],
      contextRef: const {
        'kind': 'classic',
        'sourceId': 'classic:shanghan',
        'anchorId': 'classic:shanghan:2',
        'anchorVersion': 'sha256:abc',
      },
    );

    final result = SessionStateSnapshotBuilder.build(
      sessionId: sessionId,
      taskOwnerSessionId: sessionId,
      taskState: task,
      messages: [
        {
          'id': 10,
          'conversation_id': sessionId,
          'role': 'user',
          'content': '我最近口苦，睡眠浅。',
          'metadata': null,
        },
        {
          'id': 11,
          'conversation_id': sessionId,
          'role': 'assistant',
          'content': '助手曾经回答的内容不能成为用户事实。',
          'metadata': metadata.encode(),
        },
      ],
    );

    expect(result.status, SessionStateStatus.restored);
    expect(result.sessionId, sessionId);
    expect(result.activeTaskId, 'task-7');

    final original = result.facts.singleWhere(
      (fact) => fact.provenance == SessionFactProvenance.userOriginal,
    );
    expect(original.value, '我最近口苦，睡眠浅。');

    final confirmed = result.facts
        .where((fact) => fact.provenance == SessionFactProvenance.userConfirmed)
        .map((fact) => fact.key)
        .toSet();
    expect(confirmed, contains('selected_symptom'));
    expect(confirmed, contains('interview_answer:temperature'));
    expect(confirmed, contains('rule_question_answer:q1'));
    expect(confirmed, contains('confirmed_pending_answer:sleep'));

    expect(
      result.facts.where((fact) => fact.value ==
          '助手曾经回答的内容不能成为用户事实。'),
      isEmpty,
    );
    expect(result.evidenceReferences, hasLength(2));
    expect(
      result.evidenceReferences.every((ref) => ref.sourceVersion == 'UNKNOWN'),
      isTrue,
    );
    expect(result.evidenceReferences.map((ref) => ref.evidenceId),
        contains('classic:shanghan:2'));
  });

  test('tool-role invocation ledger metadata is excluded from memory evidence', () {
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      messages: [
        {
          'id': 1,
          'conversation_id': 7,
          'role': 'assistant',
          'content': '正常助手回答',
          'metadata': AssistantMessageMetadata(
            sourceIds: const ['source:visible-answer'],
          ).encode(),
        },
        {
          'id': 2,
          'conversation_id': 7,
          'role': 'tool',
          'content': 'TOOL_INVOCATION_TERMINAL',
          'metadata': AssistantMessageMetadata(
            sourceIds: const ['private:tool-ledger-source'],
          ).encode(),
        },
      ],
    );

    expect(
      result.evidenceReferences.map((item) => item.sourceId).toList(),
      ['source:visible-answer'],
    );
    expect(
      result.evidenceReferences.any(
        (item) => item.sourceId == 'private:tool-ledger-source',
      ),
      isFalse,
    );
    expect(
      result.facts.any((item) => item.value == 'TOOL_INVOCATION_TERMINAL'),
      isFalse,
    );
  });

  test('a message from another conversation fails the entire snapshot closed', () {
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      messages: [
        {
          'id': 1,
          'conversation_id': 7,
          'role': 'user',
          'content': '当前会话内容',
        },
        {
          'id': 2,
          'conversation_id': 8,
          'role': 'assistant',
          'content': '不得混入另一个会话',
        },
      ],
    );

    expect(result.status, SessionStateStatus.sessionMismatch);
    expect(result.facts, isEmpty);
    expect(result.evidenceReferences, isEmpty);
    expect(result.activeTaskId, isNull);
  });

  test('a TCM task without a matching owner session is rejected', () {
    final task = TcmInterviewTaskState(
      taskId: 'task-8',
      snapshot: snapshot(answers: const {'temperature': 'fever_chills'}),
      status: 'in_progress',
    );
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      taskOwnerSessionId: 8,
      taskState: task,
      messages: const [],
    );

    expect(result.status, SessionStateStatus.sessionMismatch);
    expect(result.facts, isEmpty);
    expect(result.activeTaskId, isNull);
  });

  test('empty memory is UNKNOWN rather than an empty restored session', () {
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      messages: const [],
    );

    expect(result.status, SessionStateStatus.unknown);
    expect(result.facts, isEmpty);
    expect(result.diagnostics, contains('TCM_TASK_STATE_NOT_PRESENT'));
  });

  test('oversized and excess user originals are omitted without truncation', () {
    // Deliberately reverse the DB row order. The builder must normalize by ID.
    final messages = [
      {
        'id': 11,
        'conversation_id': 7,
        'role': 'user',
        'content': List<String>.filled(1201, 'x').join(),
      },
      for (var id = 10; id >= 1; id--)
        {
          'id': id,
          'conversation_id': 7,
          'role': 'user',
          'content': 'message-$id',
        },
    ];
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      messages: messages,
    );

    expect(result.status, SessionStateStatus.partial);
    expect(result.omittedUserMessageCount, 3);
    expect(result.facts, hasLength(8));
    expect(result.facts.first.value, 'message-3');
    expect(result.facts.last.value, 'message-10');
  });


  test('assistant-only display rows do not create restored memory facts', () {
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      messages: [
        {
          'id': 1,
          'conversation_id': 7,
          'role': 'assistant',
          'content': '仅有助手展示文本',
        },
      ],
    );

    expect(result.status, SessionStateStatus.unknown);
    expect(result.facts, isEmpty);
  });

  test('extracts only user role rows as USER_ORIGINAL', () {
    final result = SessionStateSnapshotBuilder.build(
      sessionId: 7,
      messages: [
        {
          'id': 1,
          'conversation_id': 7,
          'role': 'system',
          'content': 'system prompt',
        },
        {
          'id': 2,
          'conversation_id': 7,
          'role': 'tool',
          'content': 'tool output',
        },
        {
          'id': 3,
          'conversation_id': 7,
          'role': 'assistant',
          'content': 'assistant answer',
        },
        {
          'id': 4,
          'conversation_id': 7,
          'role': 'user',
          'content': '用户原话',
        },
      ],
    );

    expect(result.status, SessionStateStatus.restored);
    expect(result.facts, hasLength(1));
    expect(result.facts.single.value, '用户原话');
    expect(result.facts.single.provenance, SessionFactProvenance.userOriginal);
  });
}
