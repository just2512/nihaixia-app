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
        if (normalizedTraceId != null) 'traceId': normalizedTraceId,
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
        if (normalizedTraceId != null) 'traceId': normalizedTraceId,
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
        if (normalizedTraceId != null) 'traceId': normalizedTraceId,
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
        'traceId',
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
    if (response?['traceId'] != expectedTraceId) {
      throw PlatformException(
        code: 'TRACE_ID_MISMATCH',
        message: 'Native 响应未返回与请求一致的 TRACE ID',
      );
    }
  }

  Future<LocalAiSymptomDraft> extractSymptoms() async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'extractSymptoms',
    );
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
