import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/utils/ziwei_plate_layout.dart';

void main() {
  group('Find N2 紫微星盘宽度策略', () {
    test('外屏按可用宽度收缩，不强行撑满固定宽度', () {
      expect(ziweiPlateWidthFor(360), 360);
      expect(ziweiPlateWidthFor(390), 390);
    });

    test('640dp 至 700dp 过渡区不再出现宽度反跳', () {
      expect(ziweiPlateWidthFor(640), 640);
      expect(ziweiPlateWidthFor(650), 640);
      expect(ziweiPlateWidthFor(699), 640);
      expect(ziweiPlateWidthFor(700), 640);
    });

    test('展开内屏与更宽桌面窗口统一限制最大盘面宽度', () {
      expect(ziweiPlateWidthFor(775), 640);
      expect(ziweiPlateWidthFor(1200), 640);
    });

    test('非有限窗口宽度回退到安全最大宽度', () {
      expect(ziweiPlateWidthFor(double.infinity), 640);
      expect(ziweiPlateWidthFor(double.nan), 640);
    });

    test('自定义最大宽度必须是有限正数', () {
      expect(
        () => ziweiPlateWidthFor(700, maxWidth: 0),
        throwsArgumentError,
      );
      expect(
        () => ziweiPlateWidthFor(700, maxWidth: double.infinity),
        throwsArgumentError,
      );
    });
  });
}
