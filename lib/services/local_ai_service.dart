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
      throw const PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到本地模型状态',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }

  Future<LocalAiModelStatus> loadModel() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('loadModel');
    if (data == null) {
      throw const PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到模型加载结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }

  Future<String> sendMessage(String text) async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'sendMessage',
      {'text': text},
    );
    final reply = data?['reply'] as String?;
    if (reply == null || reply.trim().isEmpty) {
      throw const PlatformException(
        code: 'EMPTY_REPLY',
        message: '模型没有返回有效文本',
      );
    }
    return reply;
  }

  Future<LocalAiModelStatus> resetConversation() async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'resetConversation',
    );
    if (data == null) {
      throw const PlatformException(
        code: 'EMPTY_STATUS',
        message: '没有收到会话重置结果',
      );
    }
    return LocalAiModelStatus.fromMap(data);
  }
}

class LocalAiModelStatus {
  final bool installed;
  final bool ready;
  final String modelPath;
  final int sizeBytes;
  final String backend;

  const LocalAiModelStatus({
    required this.installed,
    required this.ready,
    required this.modelPath,
    required this.sizeBytes,
    required this.backend,
  });

  factory LocalAiModelStatus.fromMap(Map<String, dynamic> map) {
    return LocalAiModelStatus(
      installed: map['installed'] == true,
      ready: map['ready'] == true,
      modelPath: map['modelPath'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      backend: map['backend'] as String? ?? 'not_loaded',
    );
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '尚未安装';
    final gb = sizeBytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }
}
