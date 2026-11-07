/// Pure layout policy for the Ziwei 4×4 chart on foldable displays.
///
/// The plate fills narrow windows and stops growing at [maxWidth]. Keeping
/// this calculation outside the widget makes breakpoint regressions testable
/// without relying on a particular physical device.
double ziweiPlateWidthFor(
  double availableWidth, {
  double maxWidth = 640,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) {
    throw ArgumentError.value(maxWidth, 'maxWidth', 'must be finite and > 0');
  }
  if (!availableWidth.isFinite) return maxWidth;
  return availableWidth.clamp(0.0, maxWidth).toDouble();
}
