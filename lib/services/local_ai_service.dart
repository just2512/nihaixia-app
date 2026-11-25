import 'dart:convert';
import 'package:flutter/services.dart';

/// Android 本地 Gemma 4 E4B 通道。
///
/// 模型文件存放在应用私有目录，不进入 APK；非 Android 平台明确返回不可用。
class LocalAiService {
  static const MethodChannel _channel =
      MethodChannel('com.nihaisha.app/local_ai');

  Future<LocalAiModelStatus> getStatus() async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'getModelStatus',
    );
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到本地模型状态',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }

  Future<LocalAiModelStatus> loadModel() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('loadModel');
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到模型加载结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }

  /// Persists the user's preferred E4B backend. If a Native model is
  /// currently loaded, Android releases and rebuilds it on the serialized AI
  /// queue while restoring only completed conversation turns.
  Future<LocalAiModelStatus> setBackendPreference(String backend) async {
    final normalized = backend.trim().toLowerCase();
    if (normalized != 'gpu' && normalized != 'cpu') {
      throw ArgumentError.value(backend, 'backend', '只支持 GPU 或 CPU');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'setBackendPreference',
      {'backend': normalized},
    );
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到推理后端设置结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }

  Future<LocalAiModelStatus> importModel() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('importModel');
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到模型导入结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }

  Future<String> sendMessage(
    String text, {
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) =>
      _sendTextMessage(
        text,
        requireMedicalSafety: requireMedicalSafety,
        redFlagContext: redFlagContext,
        redFlagContextTruncated: redFlagContextTruncated,
      );

  Future<String> sendMessageWithTrace(
    String text, {
    required String traceId,
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) =>
      _sendTextMessage(
        text,
        traceId: traceId,
        requireMedicalSafety: requireMedicalSafety,
        redFlagContext: redFlagContext,
        redFlagContextTruncated: redFlagContextTruncated,
      );

  Future<String> _sendTextMessage(
    String text, {
    String? traceId,
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'sendMessage',
      {
        'text': text,
        if (requireMedicalSafety) 'require_red_flag': true,
        if (requireMedicalSafety &&
            redFlagContext != null &&
            redFlagContext.trim().isNotEmpty)
          'red_flag_context': redFlagContext.trim(),
        if (requireMedicalSafety && redFlagContextTruncated)
          'red_flag_context_truncated': true,
        if (normalizedTraceId != null) 'trace_id': normalizedTraceId,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final reply = data?['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw PlatformException(
        code: 'EMPTY_REPLY',
        message: '模型没有返回有效文本',
      );
    }
    return reply;
  }

  /// Sends user text with bounded app-retrieved reference context.
  /// The native bridge records only [text] for symptom extraction.
  Future<String> sendMessageWithContext(
    String text, {
    required String context,
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) =>
      _sendMessageWithContext(
        text,
        context: context,
        requireMedicalSafety: requireMedicalSafety,
        redFlagContext: redFlagContext,
        redFlagContextTruncated: redFlagContextTruncated,
      );

  Future<String> sendMessageWithContextAndTrace(
    String text, {
    required String context,
    required String traceId,
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) =>
      _sendMessageWithContext(
        text,
        context: context,
        traceId: traceId,
        requireMedicalSafety: requireMedicalSafety,
        redFlagContext: redFlagContext,
        redFlagContextTruncated: redFlagContextTruncated,
      );

  Future<String> _sendMessageWithContext(
    String text, {
    required String context,
    String? traceId,
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw PlatformException(code: 'EMPTY_MESSAGE', message: '请输入内容后再发送');
    }
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'sendMessage',
      {
        'text': normalized,
        'context': context.trim(),
        if (requireMedicalSafety) 'require_red_flag': true,
        if (requireMedicalSafety &&
            redFlagContext != null &&
            redFlagContext.trim().isNotEmpty)
          'red_flag_context': redFlagContext.trim(),
        if (requireMedicalSafety && redFlagContextTruncated)
          'red_flag_context_truncated': true,
        if (normalizedTraceId != null) 'trace_id': normalizedTraceId,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final reply = data?['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw PlatformException(code: 'EMPTY_REPLY', message: '模型没有返回有效文本');
    }
    return reply;
  }

  Future<String> sendImage(
    String path, {
    String prompt = '',
    bool requireMedicalSafety = false,
  }) async {
    return _sendAttachment(
      'sendImage',
      path,
      '照片',
      prompt: prompt,
      requireMedicalSafety: requireMedicalSafety,
    );
  }

  Future<String> sendImageWithTrace(
    String path, {
    String prompt = '',
    required String traceId,
    bool requireMedicalSafety = false,
  }) async {
    return _sendAttachment(
      'sendImage',
      path,
      '照片',
      prompt: prompt,
      traceId: traceId,
      requireMedicalSafety: requireMedicalSafety,
    );
  }

  Future<String> sendAudio(
    String path, {
    String prompt = '',
    bool requireMedicalSafety = false,
  }) async {
    return _sendAttachment(
      'sendAudio',
      path,
      '录音',
      prompt: prompt,
      requireMedicalSafety: requireMedicalSafety,
    );
  }

  Future<String> sendAudioWithTrace(
    String path, {
    String prompt = '',
    required String traceId,
    bool requireMedicalSafety = false,
  }) async {
    return _sendAttachment(
      'sendAudio',
      path,
      '录音',
      prompt: prompt,
      traceId: traceId,
      requireMedicalSafety: requireMedicalSafety,
    );
  }

  Future<String> _sendAttachment(
    String method,
    String path,
    String label, {
    String prompt = '',
    String? traceId,
    bool requireMedicalSafety = false,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      method,
      {
        'path': path,
        'prompt': prompt,
        if (requireMedicalSafety) 'require_red_flag': true,
        if (normalizedTraceId != null) 'trace_id': normalizedTraceId,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final reply = data?['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw PlatformException(
        code: 'EMPTY_REPLY',
        message: '模型没有返回有效的$label分析内容',
      );
    }
    return reply;
  }

  String? _normalizeTraceId(String? traceId) {
    if (traceId == null) return null;
    final normalized = traceId.trim();
    final isLowerHex = normalized.codeUnits.every(
      (unit) =>
          (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102),
    );
    if (normalized.length != 32 || !isLowerHex) {
      throw ArgumentError.value(
        traceId,
        'trace_id',
        'TRACE ID 必须是 32 位小写十六进制标识',
      );
    }
    return normalized;
  }

  void _verifyTraceId(
    Map<String, dynamic>? response,
    String? expectedTraceId,
  ) {
    if (expectedTraceId == null) return;
    if (response?['trace_id'] != expectedTraceId) {
      throw PlatformException(
        code: 'TRACE_ID_MISMATCH',
        message: 'Native 响应未返回与请求一致的 TRACE ID',
      );
    }
  }

  Future<LocalAiIntentResolution> resolveAssistantIntentWithTrace({
    required String query,
    required List<LocalAiIntentCandidate> candidates,
    required String traceId,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || normalizedQuery.length > 2000) {
      throw const FormatException('意图识别输入为空或超出长度限制');
    }
    if (candidates.length < 2 || candidates.length > 6) {
      throw const FormatException('意图识别候选数量必须为 2–6 项');
    }
    final ids = candidates.map((candidate) => candidate.id).toSet();
    if (ids.length != candidates.length ||
        candidates.any((candidate) =>
            candidate.id.trim().isEmpty ||
            candidate.title.trim().isEmpty ||
            candidate.description.length > 300)) {
      throw const FormatException('意图识别候选结构无效');
    }
    final candidatesJson = jsonEncode(
      candidates.map((candidate) => candidate.toMap()).toList(),
    );
    if (candidatesJson.length > 6000) {
      throw const FormatException('意图识别候选上下文过长');
    }
    final normalizedTraceId = _normalizeTraceId(traceId);
    if (normalizedTraceId == null) {
      throw const FormatException('意图识别必须携带 TRACE ID');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'resolveAssistantIntent',
      {
        'text': normalizedQuery,
        'candidates': candidatesJson,
        'trace_id': normalizedTraceId,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final rawDecision = data?['decision'];
    if (rawDecision is! String || rawDecision.trim().isEmpty) {
      throw const FormatException('本地模型没有返回意图判别结果');
    }
    final backend = data?['backend'];
    if (backend is! String || backend.trim().isEmpty) {
      throw const FormatException('意图判别没有返回模型 backend');
    }
    final resolution = LocalAiIntentResolution.fromModelText(
      rawDecision,
      backend: backend,
    );
    if (resolution.action == LocalAiIntentAction.select &&
        !ids.contains(resolution.toolId)) {
      throw const FormatException('模型选择了候选集之外的工具');
    }
    return resolution;
  }

  Future<LocalAiBaziSlotDraft> extractBaziSlotsWithTrace({
    required String query,
    required Set<String> missingKeys,
    required String traceId,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || normalizedQuery.length > 2000) {
      throw const FormatException('八字参数理解输入为空或超出长度限制');
    }
    const allowedKeys = {
      'birth_date',
      'birth_time',
      'gender',
      'birthplace',
    };
    if (missingKeys.isEmpty ||
        missingKeys.length > allowedKeys.length ||
        !allowedKeys.containsAll(missingKeys)) {
      throw const FormatException('八字待补参数集合无效');
    }
    final normalizedTraceId = _normalizeTraceId(traceId);
    if (normalizedTraceId == null) {
      throw const FormatException('八字参数理解必须携带 TRACE ID');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'extractBaziSlots',
      {
        'text': normalizedQuery,
        'missing_fields': jsonEncode(missingKeys.toList(growable: false)),
        'trace_id': normalizedTraceId,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final rawDraft = data?['draft'];
    if (rawDraft is! String || rawDraft.trim().isEmpty) {
      throw const FormatException('本地模型没有返回八字参数候选');
    }
    final backend = data?['backend'];
    if (backend is! String || backend.trim().isEmpty) {
      throw const FormatException('八字参数理解没有返回模型 backend');
    }
    return LocalAiBaziSlotDraft.fromModelText(
      rawDraft,
      userText: normalizedQuery,
      requestedKeys: missingKeys,
      backend: backend,
    );
  }

  Future<LocalAiSymptomDraft> extractSymptoms() => _extractSymptoms();

  Future<LocalAiInterviewAnswer> understandTcmInterviewAnswer({
    required String questionId,
    required String question,
    required List<String> options,
    required String currentText,
    required String userContext,
    String? traceId,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final normalizedQuestionId = questionId.trim();
    final normalizedQuestion = question.trim();
    final normalizedText = currentText.trim();
    final normalizedContext = userContext.trim();
    if (normalizedQuestionId.isEmpty ||
        normalizedQuestionId.length > 80 ||
        !RegExp(r'^[a-zA-Z0-9_:]+$').hasMatch(normalizedQuestionId) ||
        normalizedQuestion.isEmpty ||
        normalizedQuestion.length > 300 ||
        normalizedText.isEmpty ||
        normalizedText.length > 2000 ||
        normalizedContext.isEmpty ||
        normalizedContext.length > 5000 ||
        !normalizedContext.contains(normalizedText) ||
        options.isEmpty ||
        options.length > 30 ||
        options.any((option) => option.trim().isEmpty || option.length > 120) ||
        options.toSet().length != options.length) {
      throw const FormatException('当前问诊问题或可选答案不符合受限理解契约');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'understandTcmInterviewAnswer',
      {
        if (normalizedTraceId != null) 'trace_id': normalizedTraceId,
        'question_id': normalizedQuestionId,
        'question': normalizedQuestion,
        'options': jsonEncode(options),
        'current_text': normalizedText,
        'user_context': normalizedContext,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final rawDraft = data?['draft'];
    if (rawDraft is! String || rawDraft.trim().isEmpty) {
      throw const FormatException('本地模型没有返回当前问项的理解结果');
    }
    return LocalAiInterviewAnswer.fromModelText(
      rawDraft,
      questionId: normalizedQuestionId,
      options: options,
      sourceText: normalizedContext,
    );
  }
  Future<LocalAiSymptomDraft> extractSymptomsWithTrace({
    required String traceId,
  }) =>
      _extractSymptoms(traceId: traceId);

  Future<LocalAiSymptomDraft> extractSymptomsWithQuestionSchema({
    required String sourceText,
    required List<Map<String, Object?>> questionSchema,
  }) =>
      _extractSymptoms(questionSchema: questionSchema, sourceText: sourceText);

  Future<LocalAiSymptomDraft> extractSymptomsWithQuestionSchemaAndTrace({
    required String traceId,
    required String sourceText,
    required List<Map<String, Object?>> questionSchema,
  }) =>
      _extractSymptoms(
        traceId: traceId,
        questionSchema: questionSchema,
        sourceText: sourceText,
      );

  Future<LocalAiSymptomDraft> extractSymptomsFromExplicitTextWithTrace({
    required String traceId,
    required String sourceText,
    required List<Map<String, Object?>> questionSchema,
    bool sourceTruncated = false,
  }) =>
      _extractSymptoms(
        traceId: traceId,
        questionSchema: questionSchema,
        sourceText: sourceText,
        sendSourceTextToNative: true,
        sourceWasTruncated: sourceTruncated,
      );

  Future<LocalAiSymptomDraft> extractSymptomsFromExplicitText({
    required String sourceText,
    required List<Map<String, Object?>> questionSchema,
    bool sourceTruncated = false,
  }) =>
      _extractSymptoms(
        questionSchema: questionSchema,
        sourceText: sourceText,
        sendSourceTextToNative: true,
        sourceWasTruncated: sourceTruncated,
      );


  Future<LocalAiSymptomDraft> _extractSymptoms({
    String? traceId,
    List<Map<String, Object?>>? questionSchema,
    String sourceText = '',
    bool sendSourceTextToNative = false,
    bool sourceWasTruncated = false,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'extractSymptoms',
      {
        if (normalizedTraceId != null) 'trace_id': normalizedTraceId,
        if (questionSchema != null) 'question_schema': jsonEncode(questionSchema),
        if (sendSourceTextToNative) 'source_text': sourceText.trim(),
        if (sendSourceTextToNative && sourceWasTruncated) 'source_truncated': true,
      },
    );
    _verifyTraceId(data, normalizedTraceId);
    final draft = data?['draft'];
    if (draft is! String || draft.trim().isEmpty) {
      throw const FormatException('模型没有返回症状整理内容');
    }
    final sourceTruncated = data?['sourceTruncated'];
    if (sourceTruncated is! bool) {
      throw const FormatException('本地问诊没有返回完整性标记，请重新整理');
    }
    final allowedQuestionOptions = <String, List<String>>{};
    final questionLabels = <String, String>{};
    for (final item in questionSchema ?? const <Map<String, Object?>>[]) {
      final id = item['id'];
      final question = item['question'];
      final rawOptions = item['options'];
      if (id is! String || question is! String || rawOptions is! List ||
          rawOptions.isEmpty || rawOptions.any((option) => option is! String)) {
        throw const FormatException('App 提供的问诊题目 schema 无效');
      }
      allowedQuestionOptions[id] = List<String>.unmodifiable(rawOptions.cast<String>());
      questionLabels[id] = question;
    }
    return LocalAiSymptomDraft.fromModelText(
      draft,
      sourceTruncated: sourceTruncated,
      sourceText: sourceText,
      allowedQuestionOptions: allowedQuestionOptions,
      questionLabels: questionLabels,
    );
  }

  Future<LocalAiModelStatus> releaseModel() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('releaseModel');
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到模型释放结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }


  /// Releases the native Engine/Conversation before deleting only cacheDir/litertlm.
  /// A partial result is returned when release or cache deletion fails.
  Future<LocalAiRuntimeCacheClearResult> clearRuntimeCache() async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'clearRuntimeCache',
    );
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_CLEAR_RESULT',
        message: '没有收到本地 AI 缓存清理结果',
      );
    }
    return LocalAiRuntimeCacheClearResult.fromMap(data);
  }

  Future<void> restoreConversation({
    required String transcript,
    required List<String> userMessages,
    bool requireMedicalSafety = false,
    String? redFlagContext,
    bool redFlagContextTruncated = false,
  }) async {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      throw const FormatException('历史对话为空，无法恢复');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'restoreConversation',
      {
        'transcript': normalized,
        'userMessages': userMessages,
        if (requireMedicalSafety) 'require_red_flag': true,
        if (requireMedicalSafety &&
            redFlagContext != null &&
            redFlagContext.trim().isNotEmpty)
          'red_flag_context': redFlagContext.trim(),
        if (requireMedicalSafety &&
            (redFlagContextTruncated || userMessages.length > 60))
          'red_flag_context_truncated': true,
      },
    );
    if (data?['restored'] != true) {
      throw PlatformException(
        code: 'RESTORE_FAILED',
        message: '本地模型没有确认历史上下文恢复完成',
      );
    }
  }

  Future<LocalAiModelStatus> resetConversation() async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'resetConversation',
    );
    if (data == null) {
      throw PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到会话重置结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }
}


enum LocalAiIntentAction { select, clarify, none }

class LocalAiIntentCandidate {
  const LocalAiIntentCandidate({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;

  Map<String, String> toMap() => {
        'id': id,
        'title': title,
        'description': description,
      };
}

class LocalAiIntentResolution {
  const LocalAiIntentResolution({
    required this.action,
    this.toolId,
    this.backend,
  });

  final LocalAiIntentAction action;
  final String? toolId;
  final String? backend;

  static const int maxModelOutputCharacters = 2000;

  factory LocalAiIntentResolution.fromModelText(
    String text, {
    String? backend,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > maxModelOutputCharacters) {
      throw const FormatException('意图判别输出为空或超出长度限制');
    }
    if (!normalized.startsWith('{') || !normalized.endsWith('}')) {
      throw const FormatException('意图判别输出必须是纯 JSON 对象');
    }
    final decoded = jsonDecode(normalized);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('意图判别结构无效');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map.keys.toSet().difference({'action', 'tool_id'}).isNotEmpty) {
      throw const FormatException('意图判别包含未声明字段');
    }
    final rawAction = map['action'];
    if (rawAction is! String) {
      throw const FormatException('意图判别 action 字段无效');
    }
    final rawToolId = map['tool_id'];
    if (rawToolId != null && rawToolId is! String) {
      throw const FormatException('意图判别 tool_id 字段无效');
    }
    final toolId = rawToolId is String ? rawToolId.trim() : null;
    switch (rawAction) {
      case 'select':
        if (toolId == null ||
            toolId.isEmpty ||
            toolId.length > 64 ||
            !RegExp(r'^[a-z0-9_]+$').hasMatch(toolId)) {
          throw const FormatException('意图判别没有返回有效候选 ID');
        }
        return LocalAiIntentResolution(
          action: LocalAiIntentAction.select,
          toolId: toolId,
          backend: backend,
        );
      case 'clarify':
        if (toolId != null && toolId.isNotEmpty) {
          throw const FormatException('澄清结果不应包含 tool_id');
        }
        return LocalAiIntentResolution(
          action: LocalAiIntentAction.clarify,
          backend: backend,
        );
      case 'none':
        if (toolId != null && toolId.isNotEmpty) {
          throw const FormatException('无工具结果不应包含 tool_id');
        }
        return LocalAiIntentResolution(
          action: LocalAiIntentAction.none,
          backend: backend,
        );
      default:
        throw const FormatException('意图判别 action 不在允许范围内');
    }
  }
}
/// E4B 提取的八字参数候选。每个值必须有用户原文中的逐字证据，
/// 并再次通过 Dart 语义校验后才可合并到确定性工具参数。
class LocalAiBaziSlotDraft {
  const LocalAiBaziSlotDraft({
    required this.values,
    this.backend,
  });

  final Map<String, String> values;
  final String? backend;

  static const Set<String> _allowedKeys = {
    'birth_date',
    'birth_time',
    'gender',
    'birthplace',
  };
  static const int maxModelOutputCharacters = 4000;

  factory LocalAiBaziSlotDraft.fromModelText(
    String text, {
    required String userText,
    required Set<String> requestedKeys,
    String? backend,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > maxModelOutputCharacters) {
      throw const FormatException('八字参数候选输出为空或超出长度限制');
    }
    if (!normalized.startsWith('{') || !normalized.endsWith('}')) {
      throw const FormatException('八字参数候选必须是纯 JSON 对象');
    }
    final decoded = jsonDecode(normalized);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('八字参数候选结构无效');
    }
    final map = Map<String, dynamic>.from(decoded);
    final keys = map.keys.toSet();
    if (keys.difference(_allowedKeys).isNotEmpty ||
        !keys.containsAll(_allowedKeys)) {
      throw const FormatException('八字参数候选必须且只能包含四个声明字段');
    }
    if (requestedKeys.isEmpty || !_allowedKeys.containsAll(requestedKeys)) {
      throw const FormatException('八字待补参数集合无效');
    }

    final verified = <String, String>{};
    for (final key in _allowedKeys) {
      final rawField = map[key];
      if (rawField is! Map ||
          rawField.keys.any((field) => field is! String)) {
        throw FormatException('八字参数候选字段 $key 结构无效');
      }
      final field = Map<String, dynamic>.from(rawField);
      if (field.keys.toSet().difference({'value', 'evidence'}).isNotEmpty ||
          !field.keys.toSet().containsAll({'value', 'evidence'})) {
        throw FormatException('八字参数候选字段 $key 必须包含 value 和 evidence');
      }
      final rawValue = field['value'];
      final rawEvidence = field['evidence'];
      if (rawValue == null && rawEvidence == null) continue;
      if (!requestedKeys.contains(key)) {
        throw FormatException('模型尝试覆盖非待补参数：$key');
      }
      if (rawValue is! String || rawEvidence is! String) {
        throw FormatException('八字参数候选字段 $key 必须同时提供文本值和证据');
      }
      final value = rawValue.trim();
      final evidence = rawEvidence.trim();
      if (value.isEmpty ||
          evidence.isEmpty ||
          value.length > 80 ||
          evidence.length > 100 ||
          !userText.contains(evidence)) {
        throw FormatException('八字参数候选字段 $key 缺少可回查的用户原文证据');
      }

      final normalizedValue = switch (key) {
        'birth_date' => _normalizeGregorianDateEvidence(evidence, userText),
        'birth_time' => _normalizeBirthTimeEvidence(evidence),
        'gender' => _normalizeGenderEvidence(evidence),
        'birthplace' => _normalizeBirthplaceEvidence(value, evidence),
        _ => null,
      };
      if (normalizedValue == null || normalizedValue != value) {
        throw FormatException('八字参数候选字段 $key 未通过原文语义校验');
      }
      verified[key] = value;
    }
    return LocalAiBaziSlotDraft(
      values: Map<String, String>.unmodifiable(verified),
      backend: backend,
    );
  }

  static String? _normalizeGregorianDateEvidence(
    String evidence,
    String userText,
  ) {
    if (userText.contains('农历') || userText.contains('阴历')) return null;
    final iso = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})')
        .firstMatch(evidence);
    final chinese = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})[日号]?')
        .firstMatch(evidence);
    final match = iso ?? chinese;
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  static String? _normalizeBirthTimeEvidence(String evidence) {
    final clock = RegExp(r'([01]?\d|2[0-3]):([0-5]\d)')
        .firstMatch(evidence);
    if (clock != null) {
      final hour = int.parse(clock.group(1)!);
      final minute = int.parse(clock.group(2)!);
      return '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    }

    final chineseTime = RegExp(
      r'(凌晨|清晨|早晨|早上|上午|中午|下午|傍晚|晚上)?\s*'
      r'([0-9零〇一二两三四五六七八九十]{1,3})(?:点|时)'
      r'(?:半|([0-9零〇一二两三四五六七八九十]{1,2})分?)?',
    ).firstMatch(evidence);
    if (chineseTime == null) return null;
    var hour = _parseSmallChineseInteger(chineseTime.group(2)!);
    final minuteToken = chineseTime.group(3);
    final minute = chineseTime[0]!.contains('半')
        ? 30
        : minuteToken == null
            ? 0
            : _parseSmallChineseInteger(minuteToken);
    if (hour == null || minute == null || minute < 0 || minute > 59) {
      return null;
    }

    final period = chineseTime.group(1);
    if (const {'凌晨', '清晨', '早晨', '早上', '上午'}.contains(period)) {
      if (hour == 12) {
        hour = 0;
      } else if (hour > 11) {
        return null;
      }
    } else if (period == '晚上' && hour == 12) {
      hour = 0;
    } else if (const {'中午', '下午', '傍晚', '晚上'}.contains(period)) {
      if (hour >= 1 && hour <= 11) {
        hour += 12;
      } else if (hour != 12) {
        return null;
      }
    } else if (hour >= 1 && hour <= 12) {
      // “八点” alone is ambiguous; do not guess AM/PM.
      return null;
    }
    if (hour < 0 || hour > 23) return null;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static int? _parseSmallChineseInteger(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value.contains('十')) {
      final parts = value.split('十');
      if (parts.length != 2 ||
          (parts[0].isNotEmpty && !digits.containsKey(parts[0])) ||
          (parts[1].isNotEmpty && !digits.containsKey(parts[1]))) {
        return null;
      }
      final tens = parts[0].isEmpty ? 1 : digits[parts[0]]!;
      final ones = parts[1].isEmpty ? 0 : digits[parts[1]]!;
      return tens * 10 + ones;
    }
    var result = 0;
    for (final character in value.split('')) {
      final digit = digits[character];
      if (digit == null) return null;
      result = result * 10 + digit;
    }
    return result;
  }

  static String? _normalizeGenderEvidence(String evidence) {
    final hasMale = RegExp(
      r'(?:男性|性别\s*[：:]?\s*男|(?:我是|本人是|我为)男(?:的|人|生)?)',
    ).hasMatch(evidence);
    final hasFemale = RegExp(
      r'(?:女性|性别\s*[：:]?\s*女|(?:我是|本人是|我为)女(?:的|人|生)?)',
    ).hasMatch(evidence);
    if (hasMale == hasFemale) return null;
    return hasMale ? 'male' : 'female';
  }

  static String? _normalizeBirthplaceEvidence(
    String value,
    String evidence,
  ) {
    final patterns = [
      RegExp(r'(?:出生地点|出生地)\s*(?:是|为|在|：|:)?\s*([^，,。；;]+)'),
      RegExp(r'(?:出生于|出生在|生于)\s*([^，,。；;]+)'),
      RegExp(r'在([^，,。；;]{1,24})出生'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(evidence);
      if (match != null && match.group(1)?.trim() == value) {
        return value;
      }
    }
    return null;
  }
}

class LocalAiRuntimeCacheClearResult {
  const LocalAiRuntimeCacheClearResult({
    required this.runtimeReleased,
    required this.cacheDeleted,
    required this.modelFileExists,
    this.errorCode,
  });

  final bool runtimeReleased;
  final bool cacheDeleted;
  final bool modelFileExists;
  final String? errorCode;

  bool get complete => runtimeReleased && cacheDeleted;

  factory LocalAiRuntimeCacheClearResult.fromMap(Map<String, dynamic> map) {
    final runtimeReleased = map['runtimeReleased'];
    final cacheDeleted = map['cacheDeleted'];
    final modelFileExists = map['modelFileExists'];
    if (runtimeReleased is! bool ||
        cacheDeleted is! bool ||
        modelFileExists is! bool) {
      throw const FormatException('本地 AI 缓存清理结果字段不完整');
    }
    return LocalAiRuntimeCacheClearResult(
      runtimeReleased: runtimeReleased,
      cacheDeleted: cacheDeleted,
      modelFileExists: modelFileExists,
      errorCode: map['errorCode'] as String?,
    );
  }
}

class LocalAiModelStatus {
  final bool installed;
  final bool fileExists;
  final bool hashVerified;
  final bool ready;
  final String modelPath;
  final int sizeBytes;
  final int expectedSizeBytes;
  final String backend;
  final String preferredBackend;
  final String? backendFallbackReason;

  const LocalAiModelStatus({
    required this.installed,
    required this.fileExists,
    required this.ready,
    required this.modelPath,
    required this.sizeBytes,
    required this.expectedSizeBytes,
    required this.backend,
    this.preferredBackend = 'gpu',
    this.hashVerified = false,
    this.backendFallbackReason,
  });

  factory LocalAiModelStatus.fromMap(Map<String, dynamic> map) {
    return LocalAiModelStatus(
      installed: map['installed'] == true,
      fileExists: map['fileExists'] == true,
      hashVerified: map['hashVerified'] == true,
      ready: map['ready'] == true,
      modelPath: map['modelPath'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      expectedSizeBytes: (map['expectedSizeBytes'] as num?)?.toInt() ?? 3659530240,
      backend: map['backend'] as String? ?? 'not_loaded',
      preferredBackend: map['preferredBackend'] as String? ?? 'gpu',
      backendFallbackReason: map['backendFallbackReason'] as String?,
    );
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '尚未安装';
    final gb = sizeBytes / 1000000000;
    return '${gb.toStringAsFixed(2)} GB';
  }
}


/// Constrained interpretation of one free-text answer to the currently pending
/// interview question. A candidate is never committed until the user taps one
/// of the existing App-provided options.
class LocalAiInterviewAnswer {
  const LocalAiInterviewAnswer({
    required this.questionId,
    this.answer,
    this.evidence,
    this.clarification,
  });

  final String questionId;
  final String? answer;
  final String? evidence;
  final String? clarification;

  bool get hasCandidate => answer != null;

  static const int maxOutputCharacters = 4000;
  static const int maxEvidenceCharacters = 200;
  static const int maxClarificationCharacters = 240;

  factory LocalAiInterviewAnswer.fromModelText(
    String text, {
    required String questionId,
    required List<String> options,
    required String sourceText,
  }) {
    final normalized = text.trim();
    if (normalized.length > maxOutputCharacters) {
      throw const FormatException('问诊回答理解内容过长');
    }
    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('问诊回答理解不是有效 JSON');
    }
    final decoded = jsonDecode(normalized.substring(start, end + 1));
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('问诊回答理解结构无效');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map.keys.toSet().difference(
          {'question_id', 'answer', 'evidence', 'clarification'},
        ).isNotEmpty ||
        !map.keys.toSet().containsAll(
          {'question_id', 'answer', 'evidence', 'clarification'},
        )) {
      throw const FormatException('问诊回答理解字段不符合契约');
    }
    if (map['question_id'] != questionId) {
      throw const FormatException('模型返回了非当前待答问项');
    }

    final rawAnswer = map['answer'];
    final rawEvidence = map['evidence'];
    final rawClarification = map['clarification'];
    if (rawAnswer == null) {
      if (rawEvidence != null || rawClarification is! String) {
        throw const FormatException('无法确认候选时必须返回澄清问题，不得附带答案证据');
      }
      final clarification = rawClarification.trim();
      if (clarification.isEmpty ||
          clarification.length > maxClarificationCharacters) {
        throw const FormatException('问诊澄清问题为空或超出长度限制');
      }
      return LocalAiInterviewAnswer(
        questionId: questionId,
        clarification: clarification,
      );
    }

    if (rawAnswer is! String ||
        rawEvidence is! String ||
        (rawClarification != null && rawClarification != '')) {
      throw const FormatException('问诊候选的答案、证据或澄清字段类型无效');
    }
    final answer = rawAnswer.trim();
    final evidence = rawEvidence.trim();
    if (!options.contains(answer) ||
        evidence.isEmpty ||
        evidence.length > maxEvidenceCharacters ||
        !sourceText.contains(evidence)) {
      throw const FormatException('问诊候选未通过当前选项白名单或用户原文证据校验');
    }
    return LocalAiInterviewAnswer(
      questionId: questionId,
      answer: answer,
      evidence: evidence,
    );
  }
}

/// One model-proposed mapping from user wording to an existing DiagnosticEngine option.
/// It remains a candidate until the user explicitly confirms it.
class LocalAiSymptomQuestionCandidate {
  const LocalAiSymptomQuestionCandidate({
    required this.questionId,
    required this.question,
    required this.answer,
    required this.evidence,
  });

  final String questionId;
  final String question;
  final String answer;
  final String evidence;
}

/// 模型从对话中提取的用户自述草稿。只保留固定字段，不接受辨证或处方字段。
class LocalAiSymptomDraft {
  final String? mainComplaint;
  final String? onset;
  final String? duration;
  final String? location;
  final String? sensation;
  final List<String> aggravatingFactors;
  final List<String> relievingFactors;
  final List<String> associatedSymptoms;
  final List<String> redFlags;
  final List<String> unknowns;
  final List<LocalAiSymptomQuestionCandidate> questionCandidates;
  final String sourceText;
  final bool sourceTruncated;

  const LocalAiSymptomDraft({
    this.mainComplaint,
    this.onset,
    this.duration,
    this.location,
    this.sensation,
    this.aggravatingFactors = const [],
    this.relievingFactors = const [],
    this.associatedSymptoms = const [],
    this.redFlags = const [],
    this.unknowns = const [],
    this.questionCandidates = const [],
    this.sourceText = '',
    this.sourceTruncated = false,
  });

  /// Limits model output before it reaches the symptom review dialog.
  /// All character limits use UTF-16 code units.
  static const int maxModelOutputCharacters = 16000;
  static const int maxFieldCharacters = 500;
  static const int maxListItems = 20;
  static const int maxListItemCharacters = 300;

  factory LocalAiSymptomDraft.fromModelText(
    String text, {
    bool sourceTruncated = false,
    String sourceText = '',
    Map<String, List<String>> allowedQuestionOptions = const {},
    Map<String, String> questionLabels = const {},
  }) {
    final normalized = text.trim();
    if (normalized.length > maxModelOutputCharacters) {
      throw const FormatException('模型返回的症状整理内容过长，请重新整理');
    }
    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('模型返回内容不是有效 JSON');
    }
    final decoded = jsonDecode(normalized.substring(start, end + 1));
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('模型返回的症状草稿结构无效');
    }
    final map = Map<String, dynamic>.from(decoded);
    String? stringValue(String key) {
      final value = map[key];
      if (value == null) return null;
      if (value is! String) {
        throw FormatException('模型返回字段 $key 的类型无效');
      }
      final trimmed = value.trim();
      if (trimmed.length > maxFieldCharacters) {
        throw FormatException('模型返回字段 $key 超出长度限制');
      }
      return trimmed.isEmpty ? null : trimmed;
    }

    List<String> stringList(String key) {
      final value = map[key];
      if (value == null) return const [];
      if (value is! List) {
        throw FormatException('模型返回字段 $key 的类型无效');
      }
      if (value.length > maxListItems) {
        throw FormatException('模型返回字段 $key 的条目过多');
      }
      final result = <String>[];
      for (final item in value) {
        if (item is! String) {
          throw FormatException('模型返回字段 $key 含有非文本条目');
        }
        final trimmed = item.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.length > maxListItemCharacters) {
          throw FormatException('模型返回字段 $key 含有过长条目');
        }
        result.add(trimmed);
      }
      return List<String>.unmodifiable(result);
    }

    final rawCandidates = map['candidate_answers'];
    final candidates = <LocalAiSymptomQuestionCandidate>[];
    if (rawCandidates != null) {
      if (rawCandidates is! List || rawCandidates.length > 20) {
        throw const FormatException('模型返回的问诊候选列表无效或过长');
      }
      final seenQuestionIds = <String>{};
      for (final rawCandidate in rawCandidates) {
        if (rawCandidate is! Map ||
            rawCandidate.keys.any((key) => key is! String)) {
          throw const FormatException('模型返回的问诊候选结构无效');
        }
        final candidate = Map<String, dynamic>.from(rawCandidate);
        if (candidate.keys.toSet().difference(
              {'question_id', 'answer', 'evidence'},
            ).isNotEmpty ||
            !candidate.keys.toSet().containsAll(
              {'question_id', 'answer', 'evidence'},
            )) {
          throw const FormatException('问诊候选字段不符合声明契约');
        }
        final questionId = candidate['question_id'];
        final answer = candidate['answer'];
        final evidence = candidate['evidence'];
        if (questionId is! String || answer is! String || evidence is! String) {
          throw const FormatException('问诊候选的题目、答案或原文证据类型无效');
        }
        final id = questionId.trim();
        final normalizedAnswer = answer.trim();
        final normalizedEvidence = evidence.trim();
        final allowed = allowedQuestionOptions[id];
        if (id.isEmpty ||
            normalizedAnswer.isEmpty ||
            normalizedEvidence.isEmpty ||
            normalizedEvidence.length > 200 ||
            sourceText.isEmpty ||
            !sourceText.contains(normalizedEvidence) ||
            allowed == null ||
            !allowed.contains(normalizedAnswer) ||
            !seenQuestionIds.add(id)) {
          throw FormatException('问诊候选 ' + id + ' 未通过选项白名单、原文证据或唯一性校验');
        }
        candidates.add(LocalAiSymptomQuestionCandidate(
          questionId: id,
          question: questionLabels[id] ?? id,
          answer: normalizedAnswer,
          evidence: normalizedEvidence,
        ));
      }
    }

    return LocalAiSymptomDraft(
      mainComplaint: stringValue('main_complaint'),
      onset: stringValue('onset'),
      duration: stringValue('duration'),
      location: stringValue('location'),
      sensation: stringValue('sensation'),
      aggravatingFactors: stringList('aggravating_factors'),
      relievingFactors: stringList('relieving_factors'),
      associatedSymptoms: stringList('associated_symptoms'),
      redFlags: stringList('red_flags'),
      unknowns: stringList('unknowns'),
      questionCandidates: List.unmodifiable(candidates),
      sourceText: sourceText.trim(),
      sourceTruncated: sourceTruncated,
    );
  }

  List<String> get summaryLines {
    final lines = <String>[];
    void add(String label, String? value) {
      if (value != null) lines.add('${label}：${value}');
    }

    void addList(String label, List<String> values) {
      if (values.isNotEmpty) lines.add('${label}：${values.join('、')}');
    }

    add('主要不适', mainComplaint);
    add('开始时间', onset);
    add('持续时间', duration);
    add('部位', location);
    add('具体感受', sensation);
    addList('加重因素', aggravatingFactors);
    addList('缓解因素', relievingFactors);
    addList('伴随表现', associatedSymptoms);
    addList('需留意的自述表现', redFlags);
    addList('仍需核实', unknowns);
    return lines;
  }
}
