import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final themes = <String, AppColors>{
    'light': AppColors.light,
    'dark': AppColors.dark,
  };

  for (final entry in themes.entries) {
    final name = entry.key;
    final colors = entry.value;

    test(name + ' theme status text tokens remain readable on page background', () {
      for (final status in <({String name, Color foreground})>[
        (name: 'danger', foreground: colors.danger),
        (name: 'warning', foreground: colors.warning),
        (name: 'success', foreground: colors.success),
        (name: 'info', foreground: colors.info),
      ]) {
        expect(
          _contrastRatio(status.foreground, colors.background),
          greaterThanOrEqualTo(4.5),
          reason: name + ' ' + status.name +
              ' text must meet 4.5:1 on its page background',
        );
      }

      expect(
        _contrastRatio(colors.onDanger, colors.danger),
        greaterThanOrEqualTo(4.5),
        reason: name + ' onDanger must remain readable on danger',
      );
    });

    test(name + ' theme status containers remain readable with onSurface text', () {
      for (final status in <({String name, Color container})>[
        (name: 'danger', container: colors.dangerContainer),
        (name: 'warning', container: colors.warningContainer),
        (name: 'success', container: colors.successContainer),
        (name: 'info', container: colors.infoContainer),
      ]) {
        expect(
          _contrastRatio(colors.onSurface, status.container),
          greaterThanOrEqualTo(4.5),
          reason: name + ' onSurface text must remain readable on ' +
              status.name + 'Container',
        );
      }
    });

    test(name + ' theme six-meridian foregrounds remain readable on their containers', () {
      final meridians = <({String name, Color foreground, Color container})>[
        (
          name: 'taiyang',
          foreground: colors.onMeridianTaiyang,
          container: colors.meridianTaiyangContainer,
        ),
        (
          name: 'yangming',
          foreground: colors.onMeridianYangming,
          container: colors.meridianYangmingContainer,
        ),
        (
          name: 'shaoyang',
          foreground: colors.onMeridianShaoyang,
          container: colors.meridianShaoyangContainer,
        ),
        (
          name: 'taiyin',
          foreground: colors.onMeridianTaiyin,
          container: colors.meridianTaiyinContainer,
        ),
        (
          name: 'shaoyin',
          foreground: colors.onMeridianShaoyin,
          container: colors.meridianShaoyinContainer,
        ),
        (
          name: 'jueyin',
          foreground: colors.onMeridianJueyin,
          container: colors.meridianJueyinContainer,
        ),
      ];

      for (final meridian in meridians) {
        expect(
          _contrastRatio(meridian.foreground, meridian.container),
          greaterThanOrEqualTo(4.5),
          reason: name + ' ' + meridian.name +
              ' foreground must meet 4.5:1 on its semantic container',
        );
      }
    });
  }
}
