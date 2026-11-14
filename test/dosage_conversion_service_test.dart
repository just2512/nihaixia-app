import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/dosage_conversion_service.dart';

void main() {
  test('重量换算复用页面既有汉制、台制、唐制系数', () {
    final han = DosageConversionService.convert(
      amount: '1',
      unit: '两',
      standard: 'han',
    );
    final tai = DosageConversionService.convert(
      amount: '1',
      unit: '两',
      standard: 'tai',
    );
    final tang = DosageConversionService.convert(
      amount: '1',
      unit: '两',
      standard: 'tang',
    );

    expect(han?.formattedResult, '15.625 克');
    expect(tai?.formattedResult, '37.5 克');
    expect(tang?.formattedResult, '13.75 克');
    expect(han?.standardAffectsCalculation, isTrue);
    expect(tang?.category, '重量');
  });

  test('容量和长度换算沿用原页面常数，不依赖重量标准', () {
    final volume = DosageConversionService.convert(
      amount: '1',
      unit: '升',
    );
    final length = DosageConversionService.convert(
      amount: '1',
      unit: '尺',
    );

    expect(volume?.formattedResult, '200 毫升');
    expect(volume?.standardAffectsCalculation, isFalse);
    expect(length?.formattedResult, '23.1 厘米');
    expect(length?.category, '长度');
  });

  test('单位在所选重量标准中不可用时拒绝转换', () {
    expect(
      DosageConversionService.convert(
        amount: '1',
        unit: '铢',
        standard: 'tai',
      ),
      isNull,
    );
    expect(
      DosageConversionService.convert(
        amount: '1',
        unit: '钱',
        standard: 'tang',
      ),
      isNull,
    );
  });

  test('无效数量、未知单位和溢出结果均拒绝转换', () {
    for (final amount in ['', '0', '-1', 'NaN', 'Infinity', '1e309']) {
      expect(
        DosageConversionService.convert(
          amount: amount,
          unit: '两',
          standard: 'han',
        ),
        isNull,
        reason: amount,
      );
    }
    expect(
      DosageConversionService.convert(
        amount: '1',
        unit: '英寸',
      ),
      isNull,
    );
    expect(
      DosageConversionService.convert(
        amount: '1e308',
        unit: '石',
        standard: 'han',
      ),
      isNull,
    );
  });

  test('格式化保留页面原精度并移除尾随零', () {
    expect(
      DosageConversionService.convert(
        amount: '1.25',
        unit: '合',
      )?.formattedResult,
      '25 毫升',
    );
    expect(
      DosageConversionService.convert(
        amount: '1',
        unit: '寸',
      )?.formattedResult,
      '2.31 厘米',
    );
  });
}
