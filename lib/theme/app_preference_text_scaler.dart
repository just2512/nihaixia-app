import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Combines the platform accessibility scaler with the app-level preference.
///
/// The platform scaler may be nonlinear (for example, Android 14+). Applying
/// the app preference to its output preserves that platform-specific curve.
@immutable
class AppPreferenceTextScaler extends TextScaler {
  const AppPreferenceTextScaler({
    required this.platformScaler,
    required this.preferenceScale,
  }) : assert(preferenceScale >= 0 && preferenceScale <= 2.0);

  final TextScaler platformScaler;
  final double preferenceScale;

  @override
  double scale(double fontSize) =>
      platformScaler.scale(fontSize) * preferenceScale;

  // Compatibility estimate only. Layout uses scale() and keeps the platform
  // scaler's nonlinear behavior.
  // ignore: deprecated_member_use
  @override
  double get textScaleFactor =>
      platformScaler.textScaleFactor * preferenceScale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppPreferenceTextScaler &&
          other.platformScaler == platformScaler &&
          other.preferenceScale == preferenceScale;

  @override
  int get hashCode => Object.hash(platformScaler, preferenceScale);
}
