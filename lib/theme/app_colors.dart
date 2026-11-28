import 'package:flutter/material.dart';

import 'yanji_palette.dart';

/// 语义化颜色唯一映射层；原始色值统一由 [YanjiPalette] 定义。
///
/// 设计方向：冷白、银灰、正红构成品牌基础色；功能灰、文字红和风险色
/// 作为语义变体。六经与工具分区色保留独立业务语义。
///
/// 使用方式：`Theme.of(context).extension<AppColors>()!`，或
/// `context.colors`（见 [AppColorsContext]）。不要在页面内写裸颜色字面量。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  // ---- 品牌主色（正红体系） ----
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  // ---- 中性系（冷白、银灰与炭黑） ----
  final Color background;
  final Color surface;
  final Color surfaceContainerHighest;
  final Color surfaceContainerLow;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color link;

  // ---- 状态系 ----
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color success;
  final Color successContainer;
  final Color info;
  final Color infoContainer;

  // ---- 六经专用色（light 深 shade / dark 亮 shade） ----
  final Color meridianTaiyang;
  final Color meridianTaiyangContainer;
  final Color onMeridianTaiyang;
  final Color meridianYangming;
  final Color meridianYangmingContainer;
  final Color onMeridianYangming;
  final Color meridianShaoyang;
  final Color meridianShaoyangContainer;
  final Color onMeridianShaoyang;
  final Color meridianTaiyin;
  final Color meridianTaiyinContainer;
  final Color onMeridianTaiyin;
  final Color meridianShaoyin;
  final Color meridianShaoyinContainer;
  final Color onMeridianShaoyin;
  final Color meridianJueyin;
  final Color meridianJueyinContainer;
  final Color onMeridianJueyin;

  // ---- 工具页分区色（通用 / 中医暖褐 / 玄学冷紫） ----
  final Color tcmZone;
  final Color metaphysicsZone;

  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.background,
    required this.surface,
    required this.surfaceContainerHighest,
    required this.surfaceContainerLow,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.link,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.success,
    required this.successContainer,
    required this.info,
    required this.infoContainer,
    required this.meridianTaiyang,
    required this.meridianTaiyangContainer,
    required this.onMeridianTaiyang,
    required this.meridianYangming,
    required this.meridianYangmingContainer,
    required this.onMeridianYangming,
    required this.meridianShaoyang,
    required this.meridianShaoyangContainer,
    required this.onMeridianShaoyang,
    required this.meridianTaiyin,
    required this.meridianTaiyinContainer,
    required this.onMeridianTaiyin,
    required this.meridianShaoyin,
    required this.meridianShaoyinContainer,
    required this.onMeridianShaoyin,
    required this.meridianJueyin,
    required this.meridianJueyinContainer,
    required this.onMeridianJueyin,
    required this.tcmZone,
    required this.metaphysicsZone,
  });

  static final AppColors light = AppColors(
    primary: YanjiPalette.brandRed,
    onPrimary: YanjiPalette.white,
    primaryContainer: YanjiPalette.lightPrimaryContainer,
    onPrimaryContainer: YanjiPalette.lightOnPrimaryContainer,
    background: YanjiPalette.coldWhite,
    surface: YanjiPalette.white,
    surfaceContainerHighest: YanjiPalette.lightSurfaceContainerHighest,
    surfaceContainerLow: YanjiPalette.lightSurfaceContainerLow,
    onSurface: YanjiPalette.charcoal,
    onSurfaceVariant: YanjiPalette.textSecondaryLight,
    outline: YanjiPalette.functionalGray,
    outlineVariant: YanjiPalette.silverGray,
    link: YanjiPalette.redOnLight,
    danger: YanjiPalette.dangerLight,
    onDanger: YanjiPalette.white,
    dangerContainer: YanjiPalette.lightErrorContainer,
    warning: YanjiPalette.warningLight,
    onWarning: YanjiPalette.white,
    warningContainer: YanjiPalette.lightWarningContainer,
    success: YanjiPalette.successLight,
    successContainer: YanjiPalette.successContainerLight,
    info: YanjiPalette.infoLight,
    infoContainer: YanjiPalette.infoContainerLight,
    meridianTaiyang: YanjiPalette.meridianTaiyangLight,
    meridianTaiyangContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianTaiyangLight, dark: false),
    onMeridianTaiyang: YanjiPalette.onMeridianLight,
    meridianYangming: YanjiPalette.meridianYangmingLight,
    meridianYangmingContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianYangmingLight, dark: false),
    onMeridianYangming: YanjiPalette.onMeridianLight,
    meridianShaoyang: YanjiPalette.meridianShaoyangLight,
    meridianShaoyangContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianShaoyangLight, dark: false),
    onMeridianShaoyang: YanjiPalette.onMeridianLight,
    meridianTaiyin: YanjiPalette.meridianTaiyinLight,
    meridianTaiyinContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianTaiyinLight, dark: false),
    onMeridianTaiyin: YanjiPalette.onMeridianLight,
    meridianShaoyin: YanjiPalette.meridianShaoyinLight,
    meridianShaoyinContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianShaoyinLight, dark: false),
    onMeridianShaoyin: YanjiPalette.onMeridianLight,
    meridianJueyin: YanjiPalette.meridianJueyinLight,
    meridianJueyinContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianJueyinLight, dark: false),
    onMeridianJueyin: YanjiPalette.onMeridianLight,
    tcmZone: YanjiPalette.tcmZoneLight,
    metaphysicsZone: YanjiPalette.metaphysicsZoneLight,
  );

  static final AppColors dark = AppColors(
    primary: YanjiPalette.darkPrimary,
    onPrimary: YanjiPalette.darkOnPrimary,
    primaryContainer: YanjiPalette.darkPrimaryContainer,
    onPrimaryContainer: YanjiPalette.darkOnPrimaryContainer,
    background: YanjiPalette.darkBackground,
    surface: YanjiPalette.darkSurface,
    surfaceContainerHighest: YanjiPalette.darkSurfaceContainer,
    surfaceContainerLow: YanjiPalette.darkSurfaceContainerLow,
    onSurface: YanjiPalette.darkOnSurface,
    onSurfaceVariant: YanjiPalette.darkTextSecondary,
    outline: YanjiPalette.darkOutline,
    outlineVariant: YanjiPalette.darkDivider,
    link: YanjiPalette.darkLink,
    danger: YanjiPalette.dangerDark,
    onDanger: YanjiPalette.onDangerDark,
    dangerContainer: YanjiPalette.darkErrorContainer,
    warning: YanjiPalette.warningDark,
    onWarning: YanjiPalette.onWarningDark,
    warningContainer: YanjiPalette.darkWarningContainer,
    success: YanjiPalette.successDark,
    successContainer: YanjiPalette.successContainerDark,
    info: YanjiPalette.infoDark,
    infoContainer: YanjiPalette.infoContainerDark,
    meridianTaiyang: YanjiPalette.meridianTaiyangDark,
    meridianTaiyangContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianTaiyangDark, dark: true),
    onMeridianTaiyang: YanjiPalette.onMeridianDark,
    meridianYangming: YanjiPalette.meridianYangmingDark,
    meridianYangmingContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianYangmingDark, dark: true),
    onMeridianYangming: YanjiPalette.onMeridianDark,
    meridianShaoyang: YanjiPalette.meridianShaoyangDark,
    meridianShaoyangContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianShaoyangDark, dark: true),
    onMeridianShaoyang: YanjiPalette.onMeridianDark,
    meridianTaiyin: YanjiPalette.meridianTaiyinDark,
    meridianTaiyinContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianTaiyinDark, dark: true),
    onMeridianTaiyin: YanjiPalette.onMeridianDark,
    meridianShaoyin: YanjiPalette.meridianShaoyinDark,
    meridianShaoyinContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianShaoyinDark, dark: true),
    onMeridianShaoyin: YanjiPalette.onMeridianDark,
    meridianJueyin: YanjiPalette.meridianJueyinDark,
    meridianJueyinContainer: YanjiPalette.meridianContainer(YanjiPalette.meridianJueyinDark, dark: true),
    onMeridianJueyin: YanjiPalette.onMeridianDark,
    tcmZone: YanjiPalette.tcmZoneDark,
    metaphysicsZone: YanjiPalette.metaphysicsZoneDark,
  );

  /// Material 3 ColorScheme 显式绑定所有角色，禁止 fromSeed 自动推导品牌色。
  /// 页面底色由 ThemeData.scaffoldBackgroundColor 单独绑定 tokens.background；
  /// surface 与 container 只代表内容表面，避免 Scaffold 被意外改成纯白卡片色。
  static ColorScheme colorSchemeFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? dark : light;
    return ColorScheme(
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      primaryContainer: tokens.primaryContainer,
      onPrimaryContainer: tokens.onPrimaryContainer,
      primaryFixed: YanjiPalette.primaryFixed,
      primaryFixedDim: YanjiPalette.primaryFixedDim,
      onPrimaryFixed: YanjiPalette.onPrimaryFixed,
      onPrimaryFixedVariant: YanjiPalette.onPrimaryFixedVariant,
      secondary: isDark ? YanjiPalette.darkSecondary : YanjiPalette.lightSecondary,
      onSecondary: isDark ? YanjiPalette.darkOnSecondary : YanjiPalette.lightOnSecondary,
      secondaryContainer: isDark
          ? YanjiPalette.darkSecondaryContainer
          : YanjiPalette.lightSecondaryContainer,
      onSecondaryContainer: isDark
          ? YanjiPalette.darkOnSecondaryContainer
          : YanjiPalette.lightOnSecondaryContainer,
      secondaryFixed: YanjiPalette.secondaryFixed,
      secondaryFixedDim: YanjiPalette.secondaryFixedDim,
      onSecondaryFixed: YanjiPalette.onSecondaryFixed,
      onSecondaryFixedVariant: YanjiPalette.onSecondaryFixedVariant,
      tertiary: isDark ? YanjiPalette.darkSecondary : YanjiPalette.lightSecondary,
      onTertiary: isDark ? YanjiPalette.darkOnSecondary : YanjiPalette.lightOnSecondary,
      tertiaryContainer: isDark
          ? YanjiPalette.darkTertiaryContainer
          : YanjiPalette.lightTertiaryContainer,
      onTertiaryContainer: isDark
          ? YanjiPalette.darkOnTertiaryContainer
          : YanjiPalette.lightOnTertiaryContainer,
      tertiaryFixed: YanjiPalette.tertiaryFixed,
      tertiaryFixedDim: YanjiPalette.tertiaryFixedDim,
      onTertiaryFixed: YanjiPalette.onTertiaryFixed,
      onTertiaryFixedVariant: YanjiPalette.onTertiaryFixedVariant,
      error: tokens.danger,
      onError: tokens.onDanger,
      errorContainer: isDark
          ? YanjiPalette.darkErrorContainer
          : YanjiPalette.lightErrorContainer,
      onErrorContainer: isDark
          ? YanjiPalette.darkOnErrorContainer
          : YanjiPalette.lightOnErrorContainer,
      surface: tokens.surface,
      onSurface: tokens.onSurface,
      surfaceDim: isDark
          ? YanjiPalette.darkBackground
          : YanjiPalette.lightSurfaceDim,
      surfaceBright: isDark
          ? YanjiPalette.darkSurfaceContainer
          : YanjiPalette.white,
      surfaceContainerLowest: isDark
          ? YanjiPalette.darkBackground
          : YanjiPalette.white,
      surfaceContainerLow: tokens.surfaceContainerLow,
      surfaceContainer: isDark
          ? YanjiPalette.darkSurface
          : YanjiPalette.lightSurfaceContainer,
      surfaceContainerHigh: isDark
          ? YanjiPalette.darkSurfaceContainerHigh
          : YanjiPalette.lightSurfaceContainerHigh,
      surfaceContainerHighest: tokens.surfaceContainerHighest,
      onSurfaceVariant: tokens.onSurfaceVariant,
      outline: tokens.outline,
      outlineVariant: tokens.outlineVariant,
      shadow: YanjiPalette.shadow,
      scrim: YanjiPalette.scrim,
      inverseSurface: isDark
          ? YanjiPalette.darkInverseSurface
          : YanjiPalette.lightInverseSurface,
      onInverseSurface: isDark
          ? YanjiPalette.darkOnInverseSurface
          : YanjiPalette.lightOnInverseSurface,
      inversePrimary: isDark
          ? YanjiPalette.darkInversePrimary
          : YanjiPalette.lightInversePrimary,
      surfaceTint: YanjiPalette.transparent,
    );
  }

  /// 六经名 → 主色（UI 层共用，替代散落的硬编码色）。
  Color meridianColor(String name) {
    switch (name) {
      case '太阳':
        return meridianTaiyang;
      case '阳明':
        return meridianYangming;
      case '少阳':
        return meridianShaoyang;
      case '太阴':
        return meridianTaiyin;
      case '少阴':
        return meridianShaoyin;
      case '厥阴':
        return meridianJueyin;
      default:
        return warning;
    }
  }

  /// 六经名 → container 色。
  Color meridianContainer(String name) {
    switch (name) {
      case '太阳':
        return meridianTaiyangContainer;
      case '阳明':
        return meridianYangmingContainer;
      case '少阳':
        return meridianShaoyangContainer;
      case '太阴':
        return meridianTaiyinContainer;
      case '少阴':
        return meridianShaoyinContainer;
      case '厥阴':
        return meridianJueyinContainer;
      default:
        return surfaceContainerHighest;
    }
  }

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? background,
    Color? surface,
    Color? surfaceContainerHighest,
    Color? surfaceContainerLow,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? link,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? success,
    Color? successContainer,
    Color? info,
    Color? infoContainer,
    Color? meridianTaiyang,
    Color? meridianTaiyangContainer,
    Color? onMeridianTaiyang,
    Color? meridianYangming,
    Color? meridianYangmingContainer,
    Color? onMeridianYangming,
    Color? meridianShaoyang,
    Color? meridianShaoyangContainer,
    Color? onMeridianShaoyang,
    Color? meridianTaiyin,
    Color? meridianTaiyinContainer,
    Color? onMeridianTaiyin,
    Color? meridianShaoyin,
    Color? meridianShaoyinContainer,
    Color? onMeridianShaoyin,
    Color? meridianJueyin,
    Color? meridianJueyinContainer,
    Color? onMeridianJueyin,
    Color? tcmZone,
    Color? metaphysicsZone,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      link: link ?? this.link,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      meridianTaiyang: meridianTaiyang ?? this.meridianTaiyang,
      meridianTaiyangContainer:
          meridianTaiyangContainer ?? this.meridianTaiyangContainer,
      onMeridianTaiyang: onMeridianTaiyang ?? this.onMeridianTaiyang,
      meridianYangming: meridianYangming ?? this.meridianYangming,
      meridianYangmingContainer:
          meridianYangmingContainer ?? this.meridianYangmingContainer,
      onMeridianYangming: onMeridianYangming ?? this.onMeridianYangming,
      meridianShaoyang: meridianShaoyang ?? this.meridianShaoyang,
      meridianShaoyangContainer:
          meridianShaoyangContainer ?? this.meridianShaoyangContainer,
      onMeridianShaoyang: onMeridianShaoyang ?? this.onMeridianShaoyang,
      meridianTaiyin: meridianTaiyin ?? this.meridianTaiyin,
      meridianTaiyinContainer:
          meridianTaiyinContainer ?? this.meridianTaiyinContainer,
      onMeridianTaiyin: onMeridianTaiyin ?? this.onMeridianTaiyin,
      meridianShaoyin: meridianShaoyin ?? this.meridianShaoyin,
      meridianShaoyinContainer:
          meridianShaoyinContainer ?? this.meridianShaoyinContainer,
      onMeridianShaoyin: onMeridianShaoyin ?? this.onMeridianShaoyin,
      meridianJueyin: meridianJueyin ?? this.meridianJueyin,
      meridianJueyinContainer:
          meridianJueyinContainer ?? this.meridianJueyinContainer,
      onMeridianJueyin: onMeridianJueyin ?? this.onMeridianJueyin,
      tcmZone: tcmZone ?? this.tcmZone,
      metaphysicsZone: metaphysicsZone ?? this.metaphysicsZone,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryContainer: l(primaryContainer, other.primaryContainer),
      onPrimaryContainer: l(onPrimaryContainer, other.onPrimaryContainer),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceContainerHighest:
          l(surfaceContainerHighest, other.surfaceContainerHighest),
      surfaceContainerLow: l(surfaceContainerLow, other.surfaceContainerLow),
      onSurface: l(onSurface, other.onSurface),
      onSurfaceVariant: l(onSurfaceVariant, other.onSurfaceVariant),
      outline: l(outline, other.outline),
      outlineVariant: l(outlineVariant, other.outlineVariant),
      link: l(link, other.link),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      meridianTaiyang: l(meridianTaiyang, other.meridianTaiyang),
      meridianTaiyangContainer:
          l(meridianTaiyangContainer, other.meridianTaiyangContainer),
      onMeridianTaiyang: l(onMeridianTaiyang, other.onMeridianTaiyang),
      meridianYangming: l(meridianYangming, other.meridianYangming),
      meridianYangmingContainer:
          l(meridianYangmingContainer, other.meridianYangmingContainer),
      onMeridianYangming: l(onMeridianYangming, other.onMeridianYangming),
      meridianShaoyang: l(meridianShaoyang, other.meridianShaoyang),
      meridianShaoyangContainer:
          l(meridianShaoyangContainer, other.meridianShaoyangContainer),
      onMeridianShaoyang: l(onMeridianShaoyang, other.onMeridianShaoyang),
      meridianTaiyin: l(meridianTaiyin, other.meridianTaiyin),
      meridianTaiyinContainer:
          l(meridianTaiyinContainer, other.meridianTaiyinContainer),
      onMeridianTaiyin: l(onMeridianTaiyin, other.onMeridianTaiyin),
      meridianShaoyin: l(meridianShaoyin, other.meridianShaoyin),
      meridianShaoyinContainer:
          l(meridianShaoyinContainer, other.meridianShaoyinContainer),
      onMeridianShaoyin: l(onMeridianShaoyin, other.onMeridianShaoyin),
      meridianJueyin: l(meridianJueyin, other.meridianJueyin),
      meridianJueyinContainer:
          l(meridianJueyinContainer, other.meridianJueyinContainer),
      onMeridianJueyin: l(onMeridianJueyin, other.onMeridianJueyin),
      tcmZone: l(tcmZone, other.tcmZone),
      metaphysicsZone: l(metaphysicsZone, other.metaphysicsZone),
    );
  }
}

/// 便捷读取：`context.colors.primary` 等。
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
