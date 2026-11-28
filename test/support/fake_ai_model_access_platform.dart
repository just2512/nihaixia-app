import 'package:nihaisha_app/licensing/ai_model_access_platform.dart';

class FakeAiModelAccessPlatform implements AiModelAccessPlatform {
  bool enabled = false;
  bool failEnable = false;
  bool failDisable = false;
  final List<bool> transitions = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled ? failEnable : failDisable) {
      throw const AiModelAccessPlatformFailure('injected bridge failure');
    }
    this.enabled = enabled;
    transitions.add(enabled);
  }
}
