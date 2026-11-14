/// Pure metric conversion logic shared by the legacy screen and the
/// assistant Headless adapter. This class does not calculate or recommend
/// medicine doses, prescriptions, or patient-specific quantities.
class DosageConversionService {
  static const standardLabels = <String, String>{
    'han': '汉制',
    'tai': '台制',
    'tang': '唐制',
  };

  static const weightUnits = <String>[
    '两',
    '铢',
    '斤',
    '石',
    '钱',
  ];

  static const volumeUnits = <String>['升', '合', '圭', '撮'];

  static const lengthUnits = <String>['尺', '寸'];

  static const volumeFactors = <String, double>{
    '升': 200.0,
    '合': 20.0,
    '圭': 0.5,
    '撮': 2.0,
  };

  static const lengthFactors = <String, double>{
    '尺': 23.1,
    '寸': 2.31,
  };

  static const weightFactors = <String, Map<String, double>>{
    // Existing screen constants: 1 石=29760g, 1 斤=16两=248g,
    // 1 两=24铢=15.625g, 1 铢=0.65g, 1 钱=1.5625g.
    'han': {
      '两': 15.625,
      '铢': 0.65,
      '斤': 248,
      '石': 29760,
      '钱': 1.5625,
    },
    // Existing screen constants: 1 斤=600g, 1 两=37.5g, 1 钱=3.75g.
    'tai': {
      '两': 37.5,
      '斤': 600,
      '钱': 3.75,
    },
    // Existing screen constants: 1 斤=220g, 1 两≈13.75g, 1 铢=0.573g.
    'tang': {
      '两': 13.75,
      '铢': 0.573,
      '斤': 220,
    },
  };

  static bool isKnownUnit(String unit) =>
      weightUnits.contains(unit) ||
      volumeFactors.containsKey(unit) ||
      lengthFactors.containsKey(unit);

  static bool isWeightUnit(String unit) => weightUnits.contains(unit);

  static bool needsWeightStandard(String unit) => isWeightUnit(unit);

  static DosageConversionOutput? convert({
    required String amount,
    required String unit,
    String? standard,
  }) {
    final quantity = double.tryParse(amount.trim());
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      return null;
    }
    if (!isKnownUnit(unit)) return null;
    if (standard != null && !standardLabels.containsKey(standard)) {
      return null;
    }

    final double converted;
    final String targetUnit;
    final String category;
    final int precision;
    final bool standardAffectsCalculation;

    if (isWeightUnit(unit)) {
      if (standard == null) return null;
      final factors = weightFactors[standard];
      final factor = factors?[unit];
      if (factor == null) return null;
      converted = quantity * factor;
      targetUnit = '克';
      category = '重量';
      precision = 3;
      standardAffectsCalculation = true;
    } else if (volumeFactors.containsKey(unit)) {
      converted = quantity * volumeFactors[unit]!;
      targetUnit = '毫升';
      category = '容量';
      precision = 2;
      standardAffectsCalculation = false;
    } else {
      converted = quantity * lengthFactors[unit]!;
      targetUnit = '厘米';
      category = '长度';
      precision = 2;
      standardAffectsCalculation = false;
    }

    // Reject overflow before formatting; toStringAsFixed throws for infinity.
    if (!converted.isFinite || converted <= 0) return null;

    final formattedNumber = _format(converted, precision);
    final standardLabel = standardLabels[standard] ??
        '不适用（容量/长度换算不依赖重量标准）';
    return DosageConversionOutput(
      quantity: quantity,
      inputUnit: unit,
      standard: standard,
      standardLabel: standardLabel,
      category: category,
      convertedValue: converted,
      targetUnit: targetUnit,
      formattedNumber: formattedNumber,
      formattedResult: '$formattedNumber $targetUnit',
      precision: precision,
      standardAffectsCalculation: standardAffectsCalculation,
    );
  }

  static String _format(double value, int precision) =>
      value
          .toStringAsFixed(precision)
          .replaceAll(RegExp(r'\.?0+$'), '');
}

class DosageConversionOutput {
  const DosageConversionOutput({
    required this.quantity,
    required this.inputUnit,
    required this.standard,
    required this.standardLabel,
    required this.category,
    required this.convertedValue,
    required this.targetUnit,
    required this.formattedNumber,
    required this.formattedResult,
    required this.precision,
    required this.standardAffectsCalculation,
  });

  final double quantity;
  final String inputUnit;
  final String? standard;
  final String standardLabel;
  final String category;
  final double convertedValue;
  final String targetUnit;
  final String formattedNumber;
  final String formattedResult;
  final int precision;
  final bool standardAffectsCalculation;
}
