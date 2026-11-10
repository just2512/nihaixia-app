import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/acupuncture_repository.dart';
import 'data/acupoint_repository.dart';
import 'data/changelog_repository.dart';
import 'data/formula_oral_hint_repository.dart';
import 'data/formula_repository.dart';
import 'data/herb_repository.dart';
import 'data/settings_repository.dart';
import 'data/ziwei_rules_repository.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_tokens.dart';
import 'theme/app_preference_text_scaler.dart';
import 'widgets/window_metrics_diagnostics.dart';

/// 关闭 Zoom 转场快照：快照机制会在设备动画缩放异常/手势取消时
/// 把进场页冻结在半透明帧（子午流注屏「打开模糊一大片」根因）。
const PageTransitionsTheme _pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: ZoomPageTransitionsBuilder(
      allowSnapshotting: false,
      allowEnterRouteSnapshotting: false,
    ),
  },
);

/// 全局组件样式统一层：AppBar / Card / NavigationBar / ListTile / 输入框
/// 的外观只在这里定义一次，页面无需各写各的，观感一致且全部引用设计 Token。
ThemeData _buildTheme(Brightness brightness) {
  final scheme = AppColors.colorSchemeFor(brightness);
  final tokens = brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  final titleTextStyle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: AppType.display,
    fontWeight: FontWeight.w700,
    color: tokens.onSurface,
    letterSpacing: 0.2,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    pageTransitionsTheme: _pageTransitionsTheme,
    scaffoldBackgroundColor: tokens.background,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.onSurface,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: titleTextStyle,
    ),
    textTheme: TextTheme(
      headlineMedium: titleTextStyle.merge(const TextStyle(fontSize: 28)),
      headlineSmall: titleTextStyle,
      titleLarge: titleTextStyle.merge(const TextStyle(fontSize: AppType.headline)),
      titleMedium: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: AppType.title,
        fontWeight: FontWeight.w600,
        color: tokens.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: titleTextStyle.merge(const TextStyle(fontSize: AppType.headline)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: AppType.caption,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surface,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      labelStyle: TextStyle(fontSize: AppType.caption, color: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: AppSpacing.lg,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(fontSize: AppType.body, color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w600),
      ),
    ),
    extensions: [tokens],
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FormulaRepository.load();
  await FormulaOralHintRepository.load();
  await HerbRepository.load();
  await AcupunctureRepository.load();
  await AcupointRepository.load();
  await ChangelogRepository.load();
  await SettingsRepository.instance.load();
  // 紫微解读层外置规则；加载失败会在仓库内部静默降级为内建默认值，不影响启动。
  await ZiweiRulesRepository.load();
  runApp(const NiHaishaApp());
}

class NiHaishaApp extends StatelessWidget {
  const NiHaishaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsRepository.instance,
      builder: (context, _) {
        final settings = SettingsRepository.instance;
        return MaterialApp(
          title: '汉唐中医',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const HomeScreen(),
          // 字号缩放必须放在 builder（包住整个 Navigator）：只包 home 的话，
          // push 出去的详情页/设置页和弹窗都拿不到用户字号，调到 200% 也只有
          // 首页四个 tab 变大（issue #4 相关反馈的根因）。
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: AppPreferenceTextScaler(
                  platformScaler: mediaQuery.textScaler,
                  preferenceScale: settings.textScaleFactor,
                ),
              ),
              child: WindowMetricsDiagnostics(child: child!),
            );
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          locale: const Locale('zh', 'CN'),
        );
      },
    );
  }
}
