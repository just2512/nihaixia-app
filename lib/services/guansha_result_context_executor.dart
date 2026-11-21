import '../models/assistant_tool_result.dart';
import '../engine/guansha_engine.dart' show GuanshaHit;
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

/// Builds a replayable local snapshot from the exact Headless calculation
/// already used to render the Guansha page. Exact child birth details remain
/// local and are removed by the prompt builder.
class GuanshaResultContextExecutor {
  static const moduleId = 'guansha';
  static const resultSchemaVersion = 'guansha-structured-result-v1';

  static const ruleVersion =
      'tool-executor-blob@808d3dfe62c9ad4279e726bb16d20b1d648c67bc;'
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
    final execution =
        await GuanshaToolExecutor.executeWithDetails(arguments);
    return fromExecution(execution);
  }

  /// The snapshot is derived from the same execution object that rendered the
  /// visible page. This avoids a second calculation with potentially changed
  /// settings or environmental inputs.
  static GuanshaResultContextExecution fromExecution(
    GuanshaToolExecution execution,
  ) {
    final result = execution.result;
    final chart = execution.chart;
    final hits = execution.hits;
    final settings = execution.settings;
    final arguments = result.arguments;
    const allowedArguments = {
      'birth_date',
      'birth_time',
      'gender',
      'birthplace',
    };
    if (!execution.succeeded ||
        chart == null ||
        hits == null ||
        settings == null ||
        arguments.length != allowedArguments.length ||
        arguments.keys.any((key) => !allowedArguments.contains(key)) ||
        result.validateFor(moduleId).isNotEmpty ||
        result.validateArgumentsMatch(arguments).isNotEmpty ||
        result.sourceIds.length != 3 ||
        result.sourceIds[0] != GuanshaToolExecutor.sourceId ||
        result.sourceIds[1] != GuanshaToolExecutor.dataSourceId ||
        result.sourceIds[2] != GuanshaToolExecutor.locationSourceId ||
        settings.length != 2 ||
        settings['useTrueSolarTime'] is! bool ||
        settings['distinguishZiShi'] is! bool) {
      return _failure(arguments, 'Headless 计算结果、输入、来源或历法设置不完整。');
    }

    final values = <String, Object?>{
      for (final entry in result.values.entries) entry.key: entry.value,
    };
    final pillars = [
      chart.bazi.year,
      chart.bazi.month,
      chart.bazi.day,
      chart.bazi.time,
    ].join(' ');
    final expectedHitText = hits.isEmpty
        ? '未命中本地规则库收录的关煞。'
        : hits.map(_formatHit).join('\n\n');
    final expectedDate = _formatBirthDateTime(
      arguments['birth_date']!,
      arguments['birth_time']!,
    );
    final requiredFields = const [
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
    if (expectedDate == null ||
        requiredFields.any((field) =>
            values[field] == null ||
            values[field] == 'MISSING' ||
            (values[field] is String && (values[field] as String).isEmpty)) ||
        values['出生公历'] != expectedDate ||
        values['性别'] != (arguments['gender'] == 'male' ? '男' : '女') ||
        !(values['出生地点'] as String).startsWith(arguments['birthplace']!) ||
        values['出生农历'] != chart.lunarText ||
        values['四柱'] != pillars ||
        values['真太阳时校正'] !=
            (settings['useTrueSolarTime']! ? '开启' : '关闭') ||
        values['早晚子时区分'] !=
            (settings['distinguishZiShi']! ? '开启' : '关闭') ||
        values['关煞命中数量'] != hits.length.toString() ||
        values['本地规则结果'] != expectedHitText ||
        values['规则库范围'] !=
            '本地数据集收录的 36 关与 18 条扩展煞；不代表所有民俗流派。') {
      return _failure(arguments, 'Headless 输出与同一次排盘、命中结果或设置不一致。');
    }

    final normalizedArguments =
        Map<String, String>.unmodifiable(arguments);
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
        'settings': Map<String, bool>.unmodifiable(settings),
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
  }

  static String _formatHit(GuanshaHit hit) {
    final entry = hit.entry;
    return [
      '${entry.name}（${entry.severity}；${entry.category}）',
      '判定原因：${hit.reason}',
      if (entry.jue.isNotEmpty) '口诀：${entry.jue}',
      if (entry.fanZheJi.isNotEmpty)
        '条目所载犯者忌：${entry.fanZheJi.join('；')}',
      if (entry.huaJie.isNotEmpty)
        '条目所载民俗化解：${entry.huaJie.join('；')}',
    ].join('\n');
  }

  static String? _formatBirthDateTime(String date, String time) {
    final dateMatch =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    final timeMatch = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time);
    if (dateMatch == null || timeMatch == null) return null;
    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    final hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final parsed = DateTime(year, month, day, hour, minute);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
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
