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

  Future<String> sendMessage(String text) => _sendTextMessage(text);

  Future<String> sendMessageWithTrace(
    String text, {
    required String traceId,
  }) =>
      _sendTextMessage(text, traceId: traceId);

  Future<String> _sendTextMessage(
    String text, {
    String? traceId,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'sendMessage',
      {
        'text': text,
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
  }) =>
      _sendMessageWithContext(text, context: context);

  Future<String> sendMessageWithContextAndTrace(
    String text, {
    required String context,
    required String traceId,
  }) =>
      _sendMessageWithContext(text, context: context, traceId: traceId);

  Future<String> _sendMessageWithContext(
    String text, {
    required String context,
    String? traceId,
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

  Future<String> sendImage(String path, {String prompt = ''}) async {
    return _sendAttachment('sendImage', path, '照片', prompt: prompt);
  }

  Future<String> sendImageWithTrace(
    String path, {
    String prompt = '',
    required String traceId,
  }) async {
    return _sendAttachment(
      'sendImage',
      path,
      '照片',
      prompt: prompt,
      traceId: traceId,
    );
  }

  Future<String> sendAudio(String path, {String prompt = ''}) async {
    return _sendAttachment('sendAudio', path, '录音', prompt: prompt);
  }

  Future<String> sendAudioWithTrace(
    String path, {
    String prompt = '',
    required String traceId,
  }) async {
    return _sendAttachment(
      'sendAudio',
      path,
      '录音',
      prompt: prompt,
      traceId: traceId,
    );
  }

  Future<String> _sendAttachment(
    String method,
    String path,
    String label, {
    String prompt = '',
    String? traceId,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      method,
      {
        'path': path,
        'prompt': prompt,
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

  Future<LocalAiSymptomDraft> extractSymptomsWithTrace({
    required String traceId,
  }) =>
      _extractSymptoms(traceId: traceId);

  Future<LocalAiSymptomDraft> _extractSymptoms({
    String? traceId,
  }) async {
    final normalizedTraceId = _normalizeTraceId(traceId);
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'extractSymptoms',
      {
        if (normalizedTraceId != null) 'trace_id': normalizedTraceId,
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
    return LocalAiSymptomDraft.fromModelText(
      draft,
      sourceTruncated: sourceTruncated,
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
  }) async {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      throw const FormatException('历史对话为空，无法恢复');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'restoreConversation',
      {'transcript': normalized, 'userMessages': userMessages},
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
    final iso = RegExp(r'(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})')
        .firstMatch(evidence);
    final chinese = RegExp(r'(\\d{4})年(\\d{1,2})月(\\d{1,2})[日号]?')
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
    final clock = RegExp(r'([01]?\\d|2[0-3]):([0-5]\\d)')
        .firstMatch(evidence);
    if (clock != null) {
      final hour = int.parse(clock.group(1)!);
      final minute = int.parse(clock.group(2)!);
      return '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    }

    final chineseTime = RegExp(
      r'(凌晨|清晨|早晨|早上|上午|中午|下午|傍晚|晚上)?\\s*'
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
    if (RegExp(r'(?:性别\\s*[：:]\\s*|我是|本人是|为)?男性').hasMatch(evidence)) {
      return 'male';
    }
    if (RegExp(r'(?:性别\\s*[：:]\\s*|我是|本人是|为)?女性').hasMatch(evidence)) {
      return 'female';
    }
    if (RegExp(r'性别\\s*[：:]\\s*男(?:\\b|$)').hasMatch(evidence) ||
        RegExp(r'(?:我是|本人是)男(?![朋同]).').hasMatch(evidence)) {
      return 'male';
    }
    if (RegExp(r'性别\\s*[：:]\\s*女(?:\\b|$)').hasMatch(evidence) ||
        RegExp(r'(?:我是|本人是)女(?![朋同]).').hasMatch(evidence)) {
      return 'female';
    }
    return null;
  }

  static String? _normalizeBirthplaceEvidence(
    String value,
    String evidence,
  ) {
    final patterns = [
      RegExp(r'(?:出生地点|出生地)\\s*(?:是|为|在|：|:)?\\s*([^，,。；;]+)'),
      RegExp(r'(?:出生于|生于)\\s*([^，,。；;]+)'),
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

  const LocalAiModelStatus({
    required this.installed,
    required this.fileExists,
    required this.ready,
    required this.modelPath,
    required this.sizeBytes,
    required this.expectedSizeBytes,
    required this.backend,
    this.hashVerified = false,
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
    );
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '尚未安装';
    final gb = sizeBytes / 1000000000;
    return '${gb.toStringAsFixed(2)} GB';
  }
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
