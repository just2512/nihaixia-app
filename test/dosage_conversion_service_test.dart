import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/dosage_conversion_service.dart';

void main() {
  test('汉制、台制、唐制重量换算保留原页面换算常数和精度', () {
    expect(
      DosageConversionService.convert(
        input: '1',
        unit: '两',
        standard: 'han',
      )?.formatted,
      '15.625 克',
    );
    expect(
      DosageConversionService.convert(
        input: '1',
        unit: '斤',
        standard: 'taiwan',
      )?.formatted,
      '600 克',
    );
    expect(
      DosageConversionService.convert(
        input: '1',
        unit: '两',
        standard: 'tang',
      )?.formatted,
      '13.75 克',
    );
    expect(
      DosageConversionService.convert(
        input: '1.5',
        unit: '钱',
        standard: 'han',
      )?.formatted,
      '2.344 克',
    );
  });

  test('容量和长度换算不依赖重量度量标准', () {
    expect(
      DosageConversionService.convert(input: '1', unit: '升')?.formatted,
      '200 毫升',
    );
    expect(
      DosageConversionService.convert(input: '2', unit: '合')?.formatted,
      '40 毫升',
    );
    expect(
      DosageConversionService.convert(input: '1', unit: '尺')?.formatted,
      '23.1 厘米',
    );
  });

  test('保留旧页面无效输入和不支持组合的空结果行为', () {
    for (final value in ['0', '-1', 'NaN', 'Infinity', '1e309', 'not-a-number']) {
      expect(
        DosageConversionService.formatInput(
          input: value,
          unit: '两',
          standard: 'han',
        ),
        '—',
        reason: value,
      );
    }
    expect(
      DosageConversionService.formatInput(
        input: '1',
        unit: '铢',
        standard: 'taiwan',
      ),
      '—',
    );
    expect(
      DosageConversionService.formatInput(
        input: '1',
        unit: '石',
        standard: 'tang',
      ),
      '—',
    );
  });

  test('weight requires an explicit standard; volume and length do not', () {
    expect(
      DosageConversionService.validate(input: '1', unit: '两'),
      isNotEmpty,
    );
    expect(
      DosageConversionService.validate(input: '1', unit: '升'),
      isEmpty,
    );
    expect(
      DosageConversionService.validate(input: '1', unit: '尺'),
      isEmpty,
    );
  });

  test('overflow does not become a fabricated numeric result', () {
    expect(
      DosageConversionService.convert(
        input: '1e308',
        unit: '石',
        standard: 'han',
      ),
      isNull,
    );
  });
}
