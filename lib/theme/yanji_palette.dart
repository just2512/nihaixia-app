import 'package:flutter/material.dart';

/// 研纪基础色板。业务组件必须通过 ColorScheme 或 AppColors 语义 Token 取色。
abstract final class YanjiPalette {
  // Brand core.
  static const coldWhite = Color(0xFFEBECEE);
  static const silverGray = Color(0xFFBCBBBF);
  static const brandRed = Color(0xFFD71019);

  // Neutral and light-theme functional variants.
  static const white = Color(0xFFFFFFFF);
  static const charcoal = Color(0xFF252629);
  static const functionalGray = Color(0xFF808087);
  static const textSecondaryLight = Color(0xFF64646B);
  static const redOnLight = Color(0xFFB30D15);
  static const dangerLight = Color(0xFFA61B1B);
  static const warningLight = Color(0xFF815500);

  // Light surfaces: Scaffold remains coldWhite; cards and fields use white.
  static const lightSurfaceDim = Color(0xFFE3E4E6);
  static const lightSurfaceContainerLow = Color(0xFFFAFAFB);
  static const lightSurfaceContainer = Color(0xFFF7F7F8);
  static const lightSurfaceContainerHigh = Color(0xFFF4F4F5);
  static const lightSurfaceContainerHighest = Color(0xFFF0F1F2);

  // Light semantic containers and their foregrounds.
  static const lightPrimaryContainer = Color(0xFFF8DADC);
  static const lightOnPrimaryContainer = Color(0xFF4D1117);
  static const lightErrorContainer = Color(0xFFF6DAD7);
  static const lightOnErrorContainer = Color(0xFF410E0B);
  static const lightWarningContainer = Color(0xFFF3E1C2);
  static const lightSecondary = Color(0xFF64646B);
  static const lightOnSecondary = white;
  static const lightSecondaryContainer = Color(0xFFE4E4E7);
  static const lightOnSecondaryContainer = charcoal;
  static const lightTertiaryContainer = Color(0xFFEBEBED);
  static const lightOnTertiaryContainer = charcoal;

  // Dark surfaces and functional variants.
  static const darkBackground = Color(0xFF17181B);
  static const darkSurface = Color(0xFF202227);
  static const darkSurfaceContainerLow = Color(0xFF1D2025);
  static const darkSurfaceContainerHigh = Color(0xFF25282E);
  static const darkSurfaceContainer = Color(0xFF292B31);
  static const darkOnSurface = Color(0xFFF0F1F3);
  static const darkTextSecondary = Color(0xFFB6BAC4);
  static const darkOutline = Color(0xFF8A8E98);
  static const darkDivider = Color(0xFF454951);
  static const darkPrimary = Color(0xFFFF5B62);
  static const darkOnPrimary = Color(0xFF1F0809);
  static const darkLink = Color(0xFFFF858A);
  static const dangerDark = Color(0xFFFF7B72);
  static const onDangerDark = Color(0xFF2B0B09);
  static const warningDark = Color(0xFFFFD166);
  static const onWarningDark = Color(0xFF261900);

  // Dark semantic containers and their foregrounds.
  static const darkPrimaryContainer = Color(0xFF6A252B);
  static const darkOnPrimaryContainer = Color(0xFFFFE0E2);
  static const darkErrorContainer = Color(0xFF7A2220);
  static const darkOnErrorContainer = Color(0xFFFFE0DC);
  static const darkWarningContainer = Color(0xFF6B4100);
  static const darkSecondary = Color(0xFF454951);
  static const darkOnSecondary = darkOnSurface;
  static const darkSecondaryContainer = Color(0xFF363841);
  static const darkOnSecondaryContainer = darkOnSurface;
  static const darkTertiaryContainer = Color(0xFF3B3D44);
  static const darkOnTertiaryContainer = darkOnSurface;

  // Material 3 fixed roles are identical in light and dark themes.
  static const primaryFixed = Color(0xFFFADADD);
  static const primaryFixedDim = Color(0xFFF2B7BC);
  static const onPrimaryFixed = Color(0xFF3F0B10);
  static const onPrimaryFixedVariant = Color(0xFF6B1720);
  static const secondaryFixed = Color(0xFFE4E4E7);
  static const secondaryFixedDim = Color(0xFFC8C8CC);
  static const onSecondaryFixed = Color(0xFF1F2024);
  static const onSecondaryFixedVariant = Color(0xFF4B4C54);
  static const tertiaryFixed = Color(0xFFEBEBED);
  static const tertiaryFixedDim = Color(0xFFD3D3D8);
  static const onTertiaryFixed = Color(0xFF202126);
  static const onTertiaryFixedVariant = Color(0xFF4A4B52);

  // Inverse surfaces and framework utility roles.
  static const shadow = Color(0xFF000000);
  static const scrim = Color(0x80000000);
  static const transparent = Color(0x00000000);
  static const lightInverseSurface = charcoal;
  static const lightOnInverseSurface = white;
  static const lightInversePrimary = Color(0xFFFFB3B6);
  static const darkInverseSurface = darkOnSurface;
  static const darkOnInverseSurface = charcoal;
  static const darkInversePrimary = redOnLight;

  // Existing domain and status colors are centralized here as well.
  static const successLight = Color(0xFF2E6B4F);
  static const successContainerLight = Color(0xFFD4E5DB);
  static const infoLight = Color(0xFF35638A);
  static const infoContainerLight = Color(0xFFD9E6F2);
  static const meridianTaiyangLight = Color(0xFFC0502A);
  static const meridianYangmingLight = Color(0xFFA8322C);
  static const meridianShaoyangLight = Color(0xFFB55B2A);
  static const meridianTaiyinLight = Color(0xFF35638A);
  static const meridianShaoyinLight = Color(0xFF6C4A85);
  static const meridianJueyinLight = Color(0xFF3F5660);
  static const onMeridianLight = Color(0xFF191C1E);
  static const tcmZoneLight = Color(0xFF7E4A2E);
  static const metaphysicsZoneLight = Color(0xFF5C4A7E);

  static const successDark = Color(0xFF81C784);
  static const successContainerDark = Color(0xFF1B5E20);
  static const infoDark = Color(0xFF90CAF9);
  static const infoContainerDark = Color(0xFF1E4E7A);
  static const meridianTaiyangDark = Color(0xFFFFB74D);
  static const meridianYangmingDark = Color(0xFFE57373);
  static const meridianShaoyangDark = Color(0xFFFF8A65);
  static const meridianTaiyinDark = Color(0xFF64B5F6);
  static const meridianShaoyinDark = Color(0xFFBA68C8);
  static const meridianJueyinDark = Color(0xFF90A4AE);
  static const onMeridianDark = Color(0xFFEFE9E2);
  static const tcmZoneDark = Color(0xFFD7A877);
  static const metaphysicsZoneDark = Color(0xFFB39DDB);
  static const meridianContainerTintOpacity = 0.12;

}
