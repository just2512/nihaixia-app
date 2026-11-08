import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';
import 'package:nihaisha_app/models/diagnosis.dart';
import 'package:nihaisha_app/models/tcm_interview_task_state.dart';

Future<T> _withStageTimeout<T>(String stage, Future<T> operation) async {
  return operation.timeout(
    const Duration(seconds: 45),
    onTimeout: () => throw TimeoutException(
      'SQLite persistence stage timed out: $stage',
      const Duration(seconds: 45),
    ),
  );
}

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-assistant-history-',
    );
    DatabaseHelper.configureTestDatabase(
      'assistant_history_recovery.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('sqflite FFI opens, writes, reads, and closes an explicit file', () async {
    final file = '${databaseDirectory.path}/ffi-smoke.db';
    final db = await _withStageTimeout(
      'direct FFI openDatabase',
      databaseFactoryFfi.openDatabase(file),
    );
    try {
      await _withStageTimeout(
        'direct FFI create table',
        db.execute(
          'CREATE TABLE smoke (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
        ),
      );
      await _withStageTimeout(
        'direct FFI insert',
        db.insert('smoke', {'value': 'persisted'}),
      );
      final rows = await _withStageTimeout(
        'direct FFI read',
        db.query('smoke'),
      );
      expect(rows, hasLength(1));
      expect(rows.single['value'], 'persisted');
    } finally {
      await _withStageTimeout('direct FFI close', db.close());
    }
  });

  test('SQLite reopen preserves FAILED tool arguments and resumable TCM task state',
      () async {
    final store = DatabaseHelper.instance;
    final conversationId = await _withStageTimeout(
      'create assistant conversation',
      store.createAssistantConversation(
        title: '持久化失败重试',
        mode: 'metaphysics',
      ),
    );

    await _withStageTimeout(
      'persist replayable user request',
      store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'user',
        content: '帮我推算五运六气',
        metadata: AssistantMessageMetadata(
          mode: 'metaphysics',
          selectedMode: 'automatic',
          replayable: true,
        ).encode(),
      ),
    );
    await _withStageTimeout(
      'persist FAILED tool result',
      store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'assistant',
        content: '【五运六气推算执行结果】\n执行状态：FAILED\n执行参数：date=2026-11-07',
        metadata: AssistantMessageMetadata(
          mode: 'metaphysics',
          selectedMode: 'automatic',
          toolId: 'yunqi',
          toolStatus: 'FAILED',
          toolArguments: const {'date': '2026-11-07'},
        ).encode(),
      ),
    );

    final snapshot = DiagnosticEngine().createSnapshot();
    final inProgressTask = TcmInterviewTaskState(
      taskId: 'tcm-task-1',
      snapshot: snapshot,
      status: 'in_progress',
      pendingPromptId: 'temperature',
      pendingPromptText: '当前最明显的寒热表现是什么？',
      pendingOptions: const ['发热 + 怕冷', '不发热'],
      transcript: const [
        TcmInterviewTaskMessage(text: '开始规则问诊', isUser: true),
        TcmInterviewTaskMessage(
          text: '当前最明显的寒热表现是什么？',
          isUser: false,
        ),
      ],
      updatedAt: DateTime.utc(2026, 11, 8, 2),
    );
    await _withStageTimeout(
      'persist in-progress TCM task',
      store.saveTcmInterviewTaskState(
        conversationId: conversationId,
        state: inProgressTask,
      ),
    );

    // Close and reopen the same on-disk database. This verifies SQLite
    // persistence across a connection restart, not Android process death.
    await _withStageTimeout(
      'close database before first reopen',
      DatabaseHelper.closeTestDatabase(),
    );
    DatabaseHelper.configureTestDatabase(
      'assistant_history_recovery.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );

    final conversations = await _withStageTimeout(
      'read conversations after reopen',
      store.getAssistantConversations(),
    );
    expect(conversations, hasLength(1));
    expect(conversations.single['title'], '持久化失败重试');
    expect(conversations.single['id'], conversationId);

    final restoredMessages = await _withStageTimeout(
      'read messages after reopen',
      store.getAssistantMessages(conversationId: conversationId),
    );
    expect(restoredMessages, hasLength(2));
    expect(restoredMessages.first['content'], '帮我推算五运六气');
    final failedMetadata = AssistantMessageMetadata.decode(
      restoredMessages.last['metadata']! as String,
    );
    expect(failedMetadata.toolId, 'yunqi');
    expect(failedMetadata.toolStatus, 'FAILED');
    expect(failedMetadata.toolArguments, const {'date': '2026-11-07'});

    final restoredTask = await _withStageTimeout(
      'read in-progress TCM task after reopen',
      store.getTcmInterviewTaskState(conversationId: conversationId),
    );
    expect(restoredTask, isNotNull);
    expect(restoredTask!.taskId, 'tcm-task-1');
    expect(restoredTask.status, 'in_progress');
    expect(restoredTask.pendingPromptId, 'temperature');
    expect(restoredTask.pendingOptions, const ['发热 + 怕冷', '不发热']);
    expect(restoredTask.transcript.last.text, '当前最明显的寒热表现是什么？');
    expect(restoredTask.snapshot.stage, snapshot.stage);

    await _withStageTimeout(
      'persist successful retry result as a new assistant message',
      store.saveAssistantMessage(
        conversationId: conversationId,
        role: 'assistant',
        content: '【五运六气推算执行结果】\n执行状态：SUCCEEDED\n执行参数：date=2026-11-07',
        metadata: AssistantMessageMetadata(
          mode: 'metaphysics',
          selectedMode: 'automatic',
          toolId: 'yunqi',
          toolStatus: 'SUCCEEDED',
          toolArguments: const {'date': '2026-11-07'},
        ).encode(),
      ),
    );
    final completedDiagnosis = DiagnosisResult(
      meridian: '少阳',
      pattern: '少阳证',
      patternDetail: '往来寒热，胸胁苦满。',
      formula: '小柴胡汤',
      recommendedFormulas: const ['小柴胡汤'],
      explanation: 'SQLite 结构化结果快照',
      confidence: 0.75,
      matchedSymptoms: const ['口苦'],
      followUpQuestions: const [],
      answers: const {'bitter_mouth': true},
      prescription: const FormulaPrescription(
        formulaName: '小柴胡汤',
        components: [
          PrescriptionComponent(name: '柴胡', dosage: '24g', role: '君药'),
        ],
        dosage: '水煎服',
        preparation: '先煮柴胡',
        contraindication: '须由执业中医师核实',
      ),
    );
    final completedTask = TcmInterviewTaskState(
      taskId: restoredTask.taskId,
      snapshot: restoredTask.snapshot,
      status: 'completed',
      completedDiagnosis: completedDiagnosis,
      transcript: [
        ...restoredTask.transcript,
        const TcmInterviewTaskMessage(
          text: '五运六气推算完成',
          isUser: false,
          isResult: true,
        ),
      ],
      updatedAt: DateTime.utc(2026, 11, 8, 2, 1),
    );
    await _withStageTimeout(
      'persist completed TCM task after retry',
      store.saveTcmInterviewTaskState(
        conversationId: conversationId,
        state: completedTask,
      ),
    );

    await _withStageTimeout(
      'close database before final reopen',
      DatabaseHelper.closeTestDatabase(),
    );
    DatabaseHelper.configureTestDatabase(
      'assistant_history_recovery.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );

    final finalMessages = await _withStageTimeout(
      'read successful retry result after final reopen',
      store.getAssistantMessages(conversationId: conversationId),
    );
    expect(finalMessages, hasLength(3));
    expect(
      finalMessages.last['content'],
      contains('执行状态：SUCCEEDED'),
    );
    expect(
      finalMessages.last['content'],
      contains('执行参数：date=2026-11-07'),
    );
    final successfulMetadata = AssistantMessageMetadata.decode(
      finalMessages.last['metadata']! as String,
    );
    expect(successfulMetadata.toolStatus, 'SUCCEEDED');
    expect(successfulMetadata.toolArguments, const {'date': '2026-11-07'});

    final finalTask = await _withStageTimeout(
      'read completed TCM task after final reopen',
      store.getTcmInterviewTaskState(conversationId: conversationId),
    );
    expect(finalTask, isNotNull);
    expect(finalTask!.status, 'completed');
    expect(finalTask.pendingPromptId, isNull);
    expect(finalTask.transcript.last.isResult, isTrue);
    expect(finalTask.completedDiagnosis, isNotNull);
    expect(finalTask.completedDiagnosis!.pattern, '少阳证');
    expect(finalTask.completedDiagnosis!.answers, const {'bitter_mouth': true});
    expect(
      finalTask.completedDiagnosis!.prescription!.components.single.dosage,
      '24g',
    );
  });
}
