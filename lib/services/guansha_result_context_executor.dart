import '../data/settings_repository.dart';
import '../models/assistant_tool_result.dart';
import 'ai_tool_result_snapshot.dart';
import 'guansha_tool_executor.dart';

class GuanshaResultContextExecution {
  const GuanshaResultContextExecution({
    required this.result,
    this.structuredSnapshot,
  });

  final AssistantToolResult result;
  final Map<String, Object?>? structuredSnapshot;

  bool get succeeded =>
      result.status == AssistantToolExecutionStatus.succeeded &&
      structuredSnapshot != null;
}

/// A verified, replayable snapshot of the existing deterministic Guansha page.
/// Exact child birth details remain local and are removed by the prompt builder.
class GuanshaResultContextExecutor {
  static const moduleId = 'guansha';
  static const resultSchemaVersion = 'guansha-structured-result-v1';

  static const ruleVersion =
      'tool-executor-blob@04f83785a723cc01a7033153b226cd4481facd06;'
      'guansha-engine-blob@177a9ee8b00bb3fe957768d2902a297dc236dbae;'
      'guansha-data-blob@8eec301e1bf2c5d3cdd8c6f1071e5b28cb636029;'
      'bazi-service-blob@724e5dcf4c32c22d62c5f2a1db50e81f8a0f8ffe;'
      'bazi-tool-executor-blob@d833cf1da5acd43d9e7524eda1daaa6dca65d68d;'
      'city-location-service-blob@b15894b31d08ad02dfae57d0ca42bd0bc274be48;'
      'china-cities-blob@5890184a32bc7f830df78c2fae51d7773cb72119;'
      'world-cities-blob@951216e7c7bf4ad8a18108813ec2c63a74bb92c9;'
      'settings-blob@2b1b4739e58d463d91037961886f71403e1551f4;'
      'pubspec-lock-blob@4e5066a560aa0419d8846267fc27ac1f609a4e92;'
      'bazi_core@0.6.7;ziwei_core@0.13.0';

  static Future<GuanshaResultContextExecution> executeWithSnapshot(
    Map<String, String> arguments,
  ) async {
    const allowed = {
      'birth_date',
      'birth_time',
      'gender',
      'birthplace',
    };
    if (arguments.length != allowed.length ||
        arguments.keys.any((key) => !allowed.contains(key))) {
      return _failure(
        arguments,
        '只接受 birth_date、birth_time、gender 和 birthplace 四个明确输入字段。',
      );
    }

    try {
      final settings = SettingsRepository.instance;
      if (!settings.isLoaded) await settings.load();
      final settingsBefore = <String, bool>{
        'useTrueSolarTime': settings.useTrueSolarTime,
        'distinguishZiShi': settings.distinguishZiShiEnabled,
      };

      final result = await GuanshaToolExecutor.execute(arguments);
      if (result.status != AssistantToolExecutionStatus.succeeded ||
          result.validateFor(moduleId).isNotEmpty ||
          result.validateArgumentsMatch(arguments).isNotEmpty ||
          result.arguments.length != allowed.length ||
          result.sourceIds.length != 3 ||
          result.sourceIds[0] != GuanshaToolExecutor.sourceId ||
          result.sourceIds[1] != GuanshaToolExecutor.dataSourceId ||
          result.sourceIds[2] != GuanshaToolExecutor.locationSourceId) {
        return GuanshaResultContextExecution(result: result);
      }

      final values = <String, Object?>{
        for (final entry in result.values.entries) entry.key: entry.value,
      };
      final settingsAfter = <String, bool>{
        'useTrueSolarTime': settings.useTrueSolarTime,
        'distinguishZiShi': settings.distinguishZiShiEnabled,
      };
      if (settingsBefore['useTrueSolarTime'] !=
              settingsAfter['useTrueSolarTime'] ||
          settingsBefore['distinguishZiShi'] !=
              settingsAfter['distinguishZiShi'] ||
          values['真太阳时校正'] !=
              (settingsBefore['useTrueSolarTime']! ? '开启' : '关闭') ||
          values['早晚子时区分'] !=
              (settingsBefore['distinguishZiShi']! ? '开启' : '关闭')) {
        return _failure(
          arguments,
          '计算期间历法设置发生变化或结果未记录实际设置；不生成 AI 快照。',
        );
      }

      const requiredFields = [
        '出生公历',
        '性别',
        '出生地点',
        '出生地坐标',
        '出生农历',
        '四柱',
        '真太阳时校正',
        '早晚子时区分',
        '关煞命中数量',
        '本地规则结果',
        '规则库范围',
      ];
      if (requiredFields.any((field) =>
          values[field] == null ||
          values[field] == 'MISSING' ||
          (values[field] is String && (values[field] as String).isEmpty))) {
        return _failure(arguments, '本地关煞结果缺少必要字段；不生成 AI 快照。');
      }

      final normalizedArguments =
          Map<String, String>.unmodifiable(result.arguments);
      final missingFields = values.entries
          .where((entry) =>
              entry.value == 'MISSING' ||
              (entry.value is String && (entry.value as String).isEmpty))
          .map((entry) => entry.key)
          .toList(growable: false);

      final baseSnapshot = <String, Object?>{
        'capabilityId': moduleId,
        'resultSchemaVersion': resultSchemaVersion,
        'ruleVersion': ruleVersion,
        'executionStatus': 'SUCCESS',
        'sourceIds': List<String>.unmodifiable(result.sourceIds),
        'input': <String, Object?>{
          'method': 'explicitBirthDetails',
          'arguments': normalizedArguments,
          'settings': Map<String, bool>.unmodifiable(settingsBefore),
        },
        'result': <String, Object?>{
          'values': values,
          'disclaimer': result.disclaimer ??
              '传统民俗文化参考，非医学结论；儿童健康请以正规医疗机构评估为准。',
        },
        'units': const <String, Object?>{},
        'missingFields': missingFields,
        'displaySummary':
            '本地规则命中 ${values['关煞命中数量']} 项 · ${values['规则库范围']}',
        'privacy': const <String, Object?>{
          'childBirthDetails': 'LOCAL_VERIFICATION_ONLY',
          'modelPromptPolicy': 'REDACT_EXACT_CHILD_BIRTH_DETAILS',
        },
      };
      final snapshotId =
          AiToolResultSnapshot.createStructuredId(snapshot: baseSnapshot);
      final snapshot = _deepUnmodifiable({
        ...baseSnapshot,
        'snapshotId': snapshotId,
      }) as Map<String, Object?>;
      return GuanshaResultContextExecution(
        result: result,
        structuredSnapshot: snapshot,
      );
    } catch (error) {
      return _failure(arguments, '本地关煞结果无法安全重建：$error');
    }
  }

  static GuanshaResultContextExecution _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      GuanshaResultContextExecution(
        result: AssistantToolResult(
          toolId: moduleId,
          title: '小儿关煞',
          status: AssistantToolExecutionStatus.failed,
          values: {'未执行原因': message},
          arguments: Map<String, String>.unmodifiable(arguments),
          disclaimer: '来源、输入或设置未通过验证；本次没有生成供 AI 使用的快照。',
        ),
      );

  static Object? _deepUnmodifiable(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _deepUnmodifiable(entry.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
    }
    return value;
  }
}
