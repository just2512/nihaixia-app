import 'package:flutter/services.dart';

const yanjiLocalAiAccessChannelName = 'com.nihaisha.app/local_ai';

abstract interface class AiModelAccessPlatform {
  /// Synchronizes the one process-local Native LiteRT gate.
  ///
  /// Disabling is acknowledged only after the Native task queue releases any
  /// loaded Conversation and Engine.
  Future<void> setEnabled(bool enabled);
}

class AiModelAccessPlatformFailure implements Exception {
  const AiModelAccessPlatformFailure(this.message);

  final String message;

  @override
  String toString() => 'AiModelAccessPlatformFailure: $message';
}

class MethodChannelAiModelAccessPlatform implements AiModelAccessPlatform {
  MethodChannelAiModelAccessPlatform({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(yanjiLocalAiAccessChannelName);

  final MethodChannel _channel;

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'setAiModelAccess',
        <String, Object?>{'enabled': enabled},
      );
      if (response == null || response['enabled'] != enabled) {
        throw const AiModelAccessPlatformFailure(
          'Native AI access gate acknowledgement is missing or mismatched.',
        );
      }
      if (!enabled && response['released'] != true) {
        throw const AiModelAccessPlatformFailure(
          'Native AI access gate did not confirm model resource release.',
        );
      }
    } on PlatformException catch (error) {
      throw AiModelAccessPlatformFailure(
        'Native AI access gate failed (${error.code}): '
        '${error.message ?? 'unknown platform error'}',
      );
    }
  }
}
