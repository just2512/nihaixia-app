/// Pure, deterministic unit conversion shared by the legacy dosage page
/// and the unified assistant. This class only converts units; it does not
/// provide prescriptions, dose selection, patient-specific advice, or drug
/// quantity recommendations.
class DosageConversionResult {
  const DosageConversionResult({
    required this.input,
    required this.standard,
    required this.unit,
    required this.outputValue,
    required this.outputUnit,
    required this.precision,
  });

  final String input;
  final String standard;
  final String unit;
  final double outputValue;
  final String outputUnit;
  final int precision;

  String get formattedValue =>
      DosageConversionService.formatNumber(outputValue, precision);

  String get formatted => '$formattedValue $outputUnit';
}

class DosageConversionService {
  static const standardIds = ['han', 'taiwan', 'tang'];
  static const standardLabels = ['汉制', '台制', '唐制'];

  static const weightUnits = ['两', '铢', '斤', '石', '钱'];
  static const volumeUnits = ['升', '合', '圭', '撮'];
  static const lengthUnits = ['尺', '寸'];
  static const supportedUnits = [
    ...weightUnits,
    ...volumeUnits,
    ...lengthUnits,
  ];

  // Existing factors from the legacy page. Keep these values unchanged.
  static const _weightFactors = [
    // 汉制（倪海厦讲义：1石=29760g, 1斤=16两=248g,
    // 1两=24铢=15.625g, 1铢=0.65g）
    {'两': 15.625, '铢': 0.65, '斤': 248.0, '石': 29760.0, '钱': 1.5625},
    // 台制（1斤=600g, 1两=37.5g, 1钱=3.75g；无石、铢单位）
    {'两': 37.5, '斤': 600.0, '钱': 3.75},
    // 唐制（1两≈13.75g，1斤≈220g；无石、钱单位）
    {'两': 13.75, '铢': 0.573, '斤': 220.0},
  ];

  static const _volumeFactors = {
    '升': 200.0,
    '合': 20.0,
    '圭': 0.5,
    '撮': 2.0,
  };

  static const _lengthFactors = {'尺': 23.1, '寸': 2.31};

  static bool isWeightUnit(String unit) => weightUnits.contains(unit);
  static bool isVolumeUnit(String unit) => _volumeFactors.containsKey(unit);
  static bool isLengthUnit(String unit) => _lengthFactors.containsKey(unit);

  static bool isSupported(String standard, String unit) {
    if (!supportedUnits.contains(unit)) return false;
    if (isWeightUnit(unit)) {
      final index = standardIds.indexOf(standard);
      return index >= 0 && _weightFactors[index].containsKey(unit);
    }
    return isVolumeUnit(unit) || isLengthUnit(unit);
  }

  static List<String> validate({
    required String input,
    required String unit,
    String? standard,
  }) {
    final errors = <String>[];
    final parsed = double.tryParse(input.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      errors.add('数值必须是大于 0 的有限数字');
      return List.unmodifiable(errors);
    }
    if (!supportedUnits.contains(unit)) {
      errors.add('单位不在 App 当前换算器支持范围内');
      return List.unmodifiable(errors);
    }
    if (standard != null &&
        standard.isNotEmpty &&
        !standardIds.contains(standard)) {
      errors.add('度量标准不在允许范围内');
      return List.unmodifiable(errors);
    }
    if (isWeightUnit(unit)) {
      if (standard == null || standard.isEmpty) {
        errors.add('重量单位必须明确选择汉制、台制或唐制');
        return List.unmodifiable(errors);
      }
      if (!standardIds.contains(standard)) {
        errors.add('度量标准不在允许范围内');
        return List.unmodifiable(errors);
      }
    }
    if (!isSupported(standard ?? '', unit)) {
      errors.add('$standard 不支持单位「$unit」；本次没有执行换算');
      return List.unmodifiable(errors);
    }
    final factor = _factor(standard ?? '', unit);
    if (factor == null || !(parsed * factor).isFinite) {
      errors.add('输入数值超出当前换算器可处理范围');
    }
    return List.unmodifiable(errors);
  }

  static DosageConversionResult? convert({
    required String input,
    required String unit,
    String? standard,
  }) {
    if (validate(input: input, unit: unit, standard: standard).isNotEmpty) {
      return null;
    }
    final parsed = double.parse(input.trim());
    final factor = _factor(standard ?? '', unit);
    if (factor == null) return null;

    final isWeight = isWeightUnit(unit);
    final isVolume = isVolumeUnit(unit);
    final outputUnit = isWeight ? '克' : isVolume ? '毫升' : '厘米';
    final precision = isWeight ? 3 : 2;
    return DosageConversionResult(
      input: input.trim(),
      standard: standard ?? '',
      unit: unit,
      outputValue: parsed * factor,
      outputUnit: outputUnit,
      precision: precision,
    );
  }

  static String formatInput({
    required String input,
    required String unit,
    required String standard,
  }) {
    final result = convert(input: input, unit: unit, standard: standard);
    return result?.formatted ?? '—';
  }

  static String standardLabel(String standard) {
    final index = standardIds.indexOf(standard);
    return index < 0 ? '不适用' : standardLabels[index];
  }

  static String formatNumber(double value, int precision) =>
      value.toStringAsFixed(precision).replaceAll(RegExp(r'\.?0+$'), '');

  static double? _factor(String standard, String unit) {
    if (isWeightUnit(unit)) {
      final index = standardIds.indexOf(standard);
      if (index < 0) return null;
      return _weightFactors[index][unit];
    }
    return _volumeFactors[unit] ?? _lengthFactors[unit];
  }
}
