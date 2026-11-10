import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_preference_text_scaler.dart';

void main() {
  test('app preference composes with the platform linear scaler', () {
    const scaler = AppPreferenceTextScaler(
      platformScaler: TextScaler.linear(2.0),
      preferenceScale: 1.25,
    );

    expect(scaler.scale(12), 30);
    expect(scaler.scale(24), 60);
  });

  test('app preference preserves a nonlinear platform scaling curve', () {
    const scaler = AppPreferenceTextScaler(
      platformScaler: _NonlinearTextScaler(),
      preferenceScale: 1.2,
    );

    expect(scaler.scale(12), closeTo(21.6, 1e-9));
    expect(scaler.scale(28), closeTo(47.52, 1e-9));
  });

  test('equal scaler inputs produce equal immutable scaler values', () {
    const first = AppPreferenceTextScaler(
      platformScaler: TextScaler.linear(1.5),
      preferenceScale: 1.1,
    );
    const second = AppPreferenceTextScaler(
      platformScaler: TextScaler.linear(1.5),
      preferenceScale: 1.1,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) {
    if (fontSize <= 20) return fontSize * 1.5;
    return 30 + (fontSize - 20) * 1.2;
  }

  // ignore: deprecated_member_use
  @override
  double get textScaleFactor => 1.5;
}
