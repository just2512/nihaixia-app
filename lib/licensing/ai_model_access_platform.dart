import 'package:flutter/services.dart';

const yanjiLocalAiChannelName = 'com.nihaisha.app/local_ai';

class AiModelAccessPlatformFailure implements Exception {
  const AiModelAccessPlatformFailure(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'AiModelAccessPlatformFailure($code: $message)';
}

abstract interface class AiModelAccessPlatform {
  /// Synchronizes the one verified entitlement with Native process memory.
  /// Revocation returns only after serialized Engine/Conversation teardown.
  Future<void> setAiAccess(bool allowed);
}

class MethodChannelAiModelAccessPlatform implements AiModelAccessPlatform {
  const MethodChannelAiModelAccessPlatform({MethodChannel? channel})
      : _channel = channel;

  final MethodChannel? _channel;

  @override
  Future<void> setAiAccess(bool allowed) async {
    final channel = _channel ?? const MethodChannel(yanjiLocalAiChannelName);
    try {
      final response = await channel.invokeMapMethod<String, Object?>(
        'setAiAccess',
        {'allowed': allowed},
      );
      if (response == null || response['aiAccessEnabled'] != allowed) {
        throw AiModelAccessPlatformFailure(
          'invalidPlatformResponse',
          'Native did not confirm aiAccessEnabled=$allowed',
        );
      }
    } on PlatformException catch (error) {
      throw AiModelAccessPlatformFailure(error.code, error.message);
    } on MissingPluginException {
      throw const AiModelAccessPlatformFailure('platformUnavailable');
    }
  }
}
