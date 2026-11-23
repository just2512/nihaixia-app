import 'dart:math';

import '../data/saved_chart_repository.dart';
import 'dosage_conversion_service.dart';
import 'ziwuliuzhu_calculation_service.dart';

/// Pure input/selection helpers shared by the UI and Headless executors.
///
/// This library intentionally does not import any *_tool_executor.dart file.
/// Deterministic execution remains behind HeadlessToolDispatcher.
class ToolArgumentSupport {
  const ToolArgumentSupport._();

  static Future<List<SavedChart>> loadSavedCharts() =>
      SavedChartRepository.getAll();

  static int? resolveSavedChartRecordId(
    String text,
    List<SavedChart> charts, {
    Map<String, String> pendingArguments = const {},
  }) {
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

    final pending = int.tryParse(
      pendingArguments['saved_chart_id']?.trim() ?? '',
    );
    if (pending != null) {
      return charts.any((chart) => chart.id == pending) ? pending : null;
    }

    return null;
  }

  static String? resolveSavedChartType(
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
    final lines = visible.asMap().entries.map((entry) {
      // Do not expose birth dates, gender or locations before explicit selection.
      final chart = entry.value;
      return '${entry.key + 1}. ID ${chart.id ?? 'MISSING'}';
    }).join('\n');
    final remaining = charts.length - visible.length;
    final tail = remaining > 0
        ? '\n另有 $remaining 条记录；可继续提供记录 ID。'
        : '';
    return '已保存命盘（按保存时间从新到旧）：\n$lines$tail';
  }

  static Map<String, String> prepareZiWuLiuZhuArguments(
    Map<String, String> arguments, {
    DateTime? now,
  }) {
    final prepared = <String, String>{...arguments};
    prepared.remove('at');
    final date = prepared['date'];
    final time = prepared['time'];
    if (date != null && time != null) {
      final candidate = '${date}T$time';
      if (ZiWuLiuZhuCalculationService.parseLocalAt(candidate) != null) {
        prepared['at'] = candidate;
      }
    } else if (date == null && time == null) {
      prepared['at'] =
          ZiWuLiuZhuCalculationService.formatLocalAt(now ?? DateTime.now());
    } else if (date == null && time != null) {
      final current = now ?? DateTime.now();
      final candidate = '${current.year.toString().padLeft(4, '0')}-'
          '${current.month.toString().padLeft(2, '0')}-'
          '${current.day.toString().padLeft(2, '0')}T$time';
      if (ZiWuLiuZhuCalculationService.parseLocalAt(candidate) != null) {
        prepared['date'] = candidate.substring(0, 10);
        prepared['at'] = candidate;
      }
    }
    return Map.unmodifiable(prepared);
  }

  static List<String> validateZiWuLiuZhuArguments(
    Map<String, String> arguments,
  ) {
    const allowed = {'at', 'date', 'time'};
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      return const ['包含未声明的子午流注计算参数'];
    }
    final at = arguments['at'];
    if (at == null || at.isEmpty) return const ['缺少完整的设备本地日期和时间'];
    if (ZiWuLiuZhuCalculationService.parseLocalAt(at) == null) {
      return const ['计算时间必须为有效的本地时间 YYYY-MM-DDTHH:mm（不含时区偏移）'];
    }
    final parsed = ZiWuLiuZhuCalculationService.parseLocalAt(at)!;
    final date = arguments['date'];
    if (date != null &&
        date != '${parsed.year.toString().padLeft(4, '0')}-'
            '${parsed.month.toString().padLeft(2, '0')}-'
            '${parsed.day.toString().padLeft(2, '0')}') {
      return const ['日期与最终计算时间不匹配'];
    }
    final time = arguments['time'];
    if (time != null &&
        time != '${parsed.hour.toString().padLeft(2, '0')}:'
            '${parsed.minute.toString().padLeft(2, '0')}') {
      return const ['时刻与最终计算时间不匹配'];
    }
    return const [];
  }

  static List<String> validateDosageArguments(
    Map<String, String> arguments,
  ) {
    const allowed = {'value', 'unit', 'standard'};
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      return const ['包含未声明的经方换算参数'];
    }
    final value = arguments['value']?.trim() ?? '';
    final unit = arguments['unit']?.trim() ?? '';
    final standard = arguments['standard']?.trim();
    final errors = <String>[];
    if (value.isEmpty) errors.add('缺少换算数值');
    if (unit.isEmpty) errors.add('缺少原始单位');
    if (errors.isNotEmpty) return List.unmodifiable(errors);
    errors.addAll(
      DosageConversionService.validate(
        input: value,
        unit: unit,
        standard: standard,
      ),
    );
    return List.unmodifiable(errors);
  }

  static Map<String, String> prepareYiJingArguments(
    Map<String, String> arguments, {
    DateTime? now,
    Random? rng,
  }) {
    final prepared = <String, String>{...arguments};
    final method = prepared['method'];
    if (method == 'time') {
      prepared['at'] = (now ?? DateTime.now()).toIso8601String();
    } else if (method == 'coins') {
      final random = rng ?? Random();
      final rolls = <String>[];
      for (var line = 0; line < 6; line++) {
        final heads = List<bool>.generate(3, (_) => random.nextBool())
            .where((isHead) => isHead)
            .length;
        rolls.add(switch (heads) {
          3 => '9',
          2 => '7',
          1 => '8',
          _ => '6',
        });
      }
      prepared['coins'] = rolls.join(',');
    }
    return Map<String, String>.unmodifiable(prepared);
  }
}
