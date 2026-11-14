import 'package:ziwei_core/ziwei_core.dart' show Gender, Location;

import '../data/saved_chart_repository.dart';
import '../data/settings_repository.dart';
import '../engine/bazi_twelve_stages.dart' show TwelveStageMode;
import '../models/assistant_tool_result.dart';
import 'assistant_chart_result_formatter.dart';
import 'bazi_service.dart';
import 'ziwei_engine.dart';

/// Recalculates one user-selected saved chart with the App's existing engines.
///
/// SavedChart stores birth inputs and location, not a historical calculation
/// snapshot. Recalculation uses the current App chart preferences.
class SavedChartToolExecutor {
  static const String savedChartSourcePrefix = 'local-data:saved-chart:';
  static const String baziSourceId = 'local-engine:bazi';
  static const String ziweiSourceId = 'local-engine:ziwei';

  static const Set<String> allowedArguments = {
    'saved_chart_id',
    'chart_type',
  };

  static Future<List<SavedChart>> loadSavedCharts() =>
      SavedChartRepository.getAll();

  static int? resolveRecordId(
    String text,
    List<SavedChart> charts, {
    Map<String, String> pendingArguments = const {},
  }) {
    // Explicit input in the current turn overrides the pending selection.
    final idMatch = RegExp(
      r'(?:记录\s*ID|命盘\s*ID|ID|编号|记录号|#)\s*[：:=]?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    final rawId = idMatch?.group(1);
    if (rawId != null) {
      final parsed = int.tryParse(rawId);
      return parsed != null && charts.any((chart) => chart.id == parsed)
          ? parsed
          : null;
    }

    final numericOnly = int.tryParse(
      text.trim().replaceAll(RegExp(r'[，。.!！?？\s]+$'), ''),
    );
    if (numericOnly != null) {
      return charts.any((chart) => chart.id == numericOnly)
          ? numericOnly
          : null;
    }

    final nameMatches = charts
        .where((chart) => chart.name.isNotEmpty && text.contains(chart.name))
        .toList(growable: false);
    if (nameMatches.length == 1) return nameMatches.single.id;
    if (nameMatches.length > 1) return null;

    if (RegExp(r'最近|最新|刚保存|最后保存').hasMatch(text) &&
        charts.isNotEmpty) {
      return charts.first.id;
    }

    // A short follow-up such as "八字" uses the saved ID from the prior turn.
    final pending = int.tryParse(
      pendingArguments['saved_chart_id']?.trim() ?? '',
    );
    if (pending != null) {
      return charts.any((chart) => chart.id == pending) ? pending : null;
    }

    // Even a one-row library requires an explicit record or "latest" request.
    return null;
  }

  static String? resolveChartType(
    String text, {
    String? pendingChartType,
  }) {
    final hasBazi = RegExp(r'八字|四柱|子平').hasMatch(text);
    final hasZiwei = RegExp(r'紫微|斗数').hasMatch(text);
    if (hasBazi == hasZiwei) {
      return hasBazi ? null : pendingChartType;
    }
    return hasBazi ? 'bazi' : 'ziwei';
  }

  static String formatSavedChartChoices(List<SavedChart> charts) {
    if (charts.isEmpty) return '当前命盘库没有已保存的记录。';
    final visible = charts.take(30).toList(growable: false);
    final lines = visible.map((chart) {
      // Expose only the minimum selector fields. Birth details and coordinates
      // remain inside the executor until the user selects a record and type.
      return 'ID ${chart.id ?? 'MISSING'}｜${chart.name}';
    }).join('\n');
    final remaining = charts.length - visible.length;
    final tail = remaining > 0
        ? '\n另有 $remaining 条记录；可直接提供记录名称或 ID。'
        : '';
    return '已保存命盘（按保存时间从新到旧）：\n$lines$tail';
  }

  static Future<AssistantToolResult> execute(
    Map<String, String> arguments,
  ) async {
    if (arguments.keys.any((key) => !allowedArguments.contains(key))) {
      return _failure(arguments, '包含未声明的命盘库参数；本次未执行。');
    }
    final id = int.tryParse(arguments['saved_chart_id']?.trim() ?? '');
    if (id == null || id <= 0) {
      return _failure(arguments, '缺少有效的保存记录 ID；本次未读取或重算命盘。');
    }
    final chartType = arguments['chart_type'];
    if (chartType != 'bazi' && chartType != 'ziwei') {
      return _failure(arguments, '排盘类型缺失或无效；必须明确选择八字或紫微。');
    }

    try {
      final charts = await SavedChartRepository.getAll();
      final matches = charts.where((chart) => chart.id == id).toList();
      if (matches.length != 1) {
        return _failure(arguments, '命盘库中不存在唯一匹配的记录 ID $id；本次未执行排盘。');
      }
      final saved = matches.single;
      final solar = DateTime.tryParse(saved.solarIso);
      if (solar == null) {
        return _failure(arguments, '保存记录的出生时间无效；本次未执行排盘。');
      }

      final longitude = saved.lng;
      final latitude = saved.lat;
      if (longitude != null && (longitude < -180 || longitude > 180)) {
        return _failure(arguments, '保存记录的经度超出有效范围；本次未执行排盘。');
      }
      if (latitude != null && (latitude < -90 || latitude > 90)) {
        return _failure(arguments, '保存记录的纬度超出有效范围；本次未执行排盘。');
      }

      // Match the existing chart pages: null location uses the documented
      // engine default (120E, 30N); a stored longitude without latitude uses
      // the pages' legacy latitude default of 30N.
      final location =
          longitude == null ? null : Location(longitude, latitude ?? 30);
      final locationDescription = longitude == null
          ? '保存记录未存地点坐标；App 原引擎按默认东经120°、北纬30°计算'
          : '${saved.cityName?.trim().isNotEmpty == true ? saved.cityName!.trim() : '保存地点'}'
              '（东经 ${longitude.toStringAsFixed(4)}，北纬 ${(latitude ?? 30).toStringAsFixed(4)}）';

      final settings = SettingsRepository.instance;
      final useTrueSolarTime = settings.useTrueSolarTime;
      final distinguishZiShi = settings.distinguishZiShiEnabled;
      final gender = saved.isMale ? Gender.male : Gender.female;
      late final String formatted;
      late final String engineSource;
      late final String chartLabel;

      if (chartType == 'bazi') {
        final stageMode = settings.fireEarthSame
            ? TwelveStageMode.fireEarthSame
            : TwelveStageMode.waterEarthSame;
        final chart = computeBaZiPaipan(
          solar,
          isMale: saved.isMale,
          useTrueSolarTime: useTrueSolarTime,
          twelveStageMode: stageMode,
          ratHourMode: distinguishZiShi,
          location: location,
        );
        final fortune = computeBaZiFortune(
          solar,
          isMale: saved.isMale,
          location: location,
          ratHourMode: distinguishZiShi,
          useTrueSolarTime: useTrueSolarTime,
        );
        formatted = formatBaZiChartForAssistant(
          solar: solar,
          isMale: saved.isMale,
          useTrueSolarTime: useTrueSolarTime,
          distinguishZiShi: distinguishZiShi,
          locationDescription: locationDescription,
          result: chart,
          fortune: fortune,
        );
        engineSource = baziSourceId;
        chartLabel = '八字';
      } else {
        final chart = calculateZiweiChart(
          solar: solar,
          gender: gender,
          location: location,
          useTrueSolarTime: useTrueSolarTime,
          ratHourMode: distinguishZiShi,
        );
        formatted = formatZiweiChartForAssistant(
          solar: solar,
          useTrueSolarTime: useTrueSolarTime,
          distinguishZiShi: distinguishZiShi,
          locationDescription: locationDescription,
          chart: chart,
        );
        engineSource = ziweiSourceId;
        chartLabel = '紫微斗数';
      }

      final preferenceSummary = [
        '真太阳时：${useTrueSolarTime ? '开启' : '关闭'}',
        '区分早晚子时：${distinguishZiShi ? '开启' : '关闭'}',
        if (chartType == 'bazi')
          '长生十二神：${settings.fireEarthSame ? '火土同宫' : '水土同宫'}',
      ].join('；');

      return AssistantToolResult(
        toolId: 'saved_charts',
        title: '我的命盘库',
        values: {
          '保存记录 ID': id.toString(),
          '保存记录名称': saved.name,
          '排盘类型': chartLabel,
          '出生时间': saved.solarIso,
          '性别': saved.isMale ? '男' : '女',
          '出生地点': locationDescription,
          '本次计算设置': preferenceSummary,
          '完整排盘结果': formatted,
        },
        sourceIds: [
          '$savedChartSourcePrefix$id',
          engineSource,
        ],
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer:
            '本地命盘库保存的是出生资料与地点，不是历史排盘结果快照。本次使用 App 当前排盘设置，调用原有确定性 $chartLabel 引擎重新计算；AI 只负责解释。保存地点缺失时已明确采用原引擎默认地点口径。传统命理仅供文化学习参考，不是科学预测，不用于医疗、法律或投资决策。',
      );
    } catch (error) {
      return _failure(arguments, '读取保存命盘或调用本地排盘引擎失败：$error');
    }
  }

  static AssistantToolResult _failure(
    Map<String, String> arguments,
    String message,
  ) =>
      AssistantToolResult(
        toolId: 'saved_charts',
        title: '我的命盘库',
        status: AssistantToolExecutionStatus.failed,
        values: {'未执行原因': message},
        arguments: Map<String, String>.unmodifiable(arguments),
        disclaimer: '命盘选择或保存数据校验未通过；本次没有执行排盘。',
      );
}
