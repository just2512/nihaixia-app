// P0-1 接线证明：computeBaZiPaipan 必须把 location 透传到真太阳时校正。
//
// 场景：2000-01-01 23:30（钟表时刻）。
//   - 默认（location=null，引擎按东经 120°）：真太阳时 ≈ 23:18，仍属子时；
//   - 乌鲁木齐（东经 87°）：真太阳时 ≈ 21:18（-132 分钟，方程差 ±16min 内不越界），
//     属亥时 → 时柱必须不同。
// 若两条路径时柱相同，说明 location 没有真正生效（回归 P0-1 的 bug）。
import 'package:flutter_test/flutter_test.dart';
import 'package:ziwei_core/ziwei_core.dart' show Location;

import 'package:nihaisha_app/services/bazi_service.dart';

void main() {
  test('location=null 与显式 Location(120,30) 结果一致（引擎默认口径）', () {
    final solar = DateTime(2000, 1, 1, 23, 30);
    final a = computeBaZiPaipan(solar);
    final b = computeBaZiPaipan(solar, location: const Location(120, 30));
    expect(b.bazi.time, a.bazi.time,
        reason: '显式传入默认经纬度应与 null 等价');
  });

  test('远西经度（乌鲁木齐 87°E）使命主 23:30 出生时柱改变（真太阳时生效）', () {
    final solar = DateTime(2000, 1, 1, 23, 30);
    final defaultR = computeBaZiPaipan(solar);
    final urumqi = computeBaZiPaipan(solar, location: const Location(87, 43));
    expect(urumqi.bazi.time, isNot(defaultR.bazi.time),
        reason: '87°E 的真太阳时校正应把 23:30 拉回亥时，时柱必须变化');
  });

  test('乌鲁木齐经度（87°E）应将凌晨 00:30 校正到前一日亥时', () {
    // 直接选取跨越子时边界的时间，验证经度修正确实改变时柱。
    final early = DateTime(2000, 1, 1, 0, 30);
    final a = computeBaZiPaipan(early);
    final b = computeBaZiPaipan(early, location: const Location(87, 43));
    // 00:30 在 120°E → 真太阳时约 0:18（早子，属当日，时柱=子）；
    // 在 87°E → 约 -1:42 → 属前一日 22:18 亥时（时柱与日期都可能不同）。
    expect(b.bazi.time, isNot(a.bazi.time),
        reason: '凌晨 00:30 出生，87°E 校正后跨回前一日亥时，时柱必须不同');
  });
}
