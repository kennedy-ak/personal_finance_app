import 'package:flutter/material.dart';

import 'design/tokens.dart';

export 'design/tokens.dart' show CediTokens, SemanticTint, Radii, AppType;

class AppColors {
  static const seed = Color(0xFF0E7C66);
  static const income = Color(0xFF16A34A);
  static const expense = Color(0xFFDC2626);
  static const accent = Color(0xFF8B5CF6);
  static const warning = Color(0xFFF59E0B);

  /// Kept for the few places that still paint a decorative sweep — the logo
  /// mark. No figure is ever drawn on one of these.
  static const gradStart = Color(0xFF0E7C66);
  static const gradEnd = Color(0xFF14B8A6);

  static const chart = <Color>[
    Color(0xFF0E7C66),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFEAB308),
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF97316),
    Color(0xFF06B6D4),
  ];
}

ThemeData _build(Brightness b) {
  final t = b == Brightness.dark ? CediTokens.dark : CediTokens.light;
  final dark = b == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: b,
  ).copyWith(
    primary: t.brand,
    onPrimary: t.onBrand,
    surface: t.canvas,
    onSurface: t.ink,
    onSurfaceVariant: t.inkMuted,
    surfaceContainer: t.card,
    surfaceContainerHighest: t.card,
    outline: t.outline,
    outlineVariant: t.hairline,
    error: t.expense.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppType.sans,
  );

  // The whole ramp is Inter Tight; only weight and tracking change. Figures
  // opt into tabular digits at the widget level via AppType.
  final text = base.textTheme.apply(fontFamily: AppType.sans).copyWith(
        headlineLarge: AppType.display.copyWith(color: t.ink),
        headlineMedium: AppType.title.copyWith(color: t.ink),
        titleLarge: AppType.title.copyWith(fontSize: 20, color: t.ink),
        titleMedium:
            AppType.cardTitle.copyWith(fontSize: 15, height: 1.2, color: t.ink),
        bodyLarge: AppType.body.copyWith(fontSize: 15, color: t.ink),
        bodyMedium: AppType.body.copyWith(color: t.inkBody),
        bodySmall: AppType.bodySmall.copyWith(color: t.inkMuted),
        labelLarge: AppType.label.copyWith(fontSize: 14, color: t.ink),
        labelMedium: AppType.label.copyWith(color: t.inkMuted),
      );

  return base.copyWith(
    extensions: [t],
    textTheme: text,
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    dividerColor: t.hairline,
    dividerTheme: DividerThemeData(color: t.rule, space: 1, thickness: 1),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: t.canvas,
      foregroundColor: t.ink,
      titleTextStyle: AppType.title.copyWith(fontSize: 22, color: t.ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: t.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.md,
        side: BorderSide(color: t.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: AppType.rowTitle.copyWith(color: t.ink),
      subtitleTextStyle: AppType.rowSub.copyWith(color: t.inkMuted),
      iconColor: t.inkMuted,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.field,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: AppType.body
          .copyWith(fontSize: 15, height: 1.0, color: t.inkFaint),
      labelStyle: AppType.label.copyWith(color: t.inkMuted),
      floatingLabelStyle: AppType.label.copyWith(color: t.brandInk),
      border: OutlineInputBorder(
        borderRadius: Radii.sm,
        borderSide: BorderSide(color: t.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.sm,
        borderSide: BorderSide(color: t.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Radii.sm,
        borderSide: BorderSide(color: t.brandInk, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: Radii.sm,
        borderSide: BorderSide(color: t.fieldBorderError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: Radii.sm,
        borderSide: BorderSide(color: t.fieldBorderError, width: 1.4),
      ),
      errorStyle: AppType.bodySmall
          .copyWith(fontSize: 12, height: 1.4, color: t.expense.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.brand,
        foregroundColor: t.onBrand,
        disabledBackgroundColor: t.disabledFill,
        disabledForegroundColor: t.disabledInk,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: Radii.sm),
        textStyle: AppType.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: t.outline),
        shape: RoundedRectangleBorder(borderRadius: Radii.sm),
        textStyle: AppType.button.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.brandInk,
        textStyle: AppType.label.copyWith(fontSize: 14),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: t.inkMuted),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: t.brand,
      labelStyle: AppType.label.copyWith(fontSize: 13, color: t.inkBody),
      secondaryLabelStyle: AppType.label.copyWith(fontSize: 13, color: t.onBrand),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: t.outline),
      ),
      side: BorderSide(color: t.outline),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.ink,
      unselectedLabelColor: t.inkMuted,
      indicatorColor: t.brandInk,
      dividerColor: Colors.transparent,
      labelStyle: AppType.label.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: AppType.label.copyWith(fontSize: 13),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.canvas,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Radii.lg),
      titleTextStyle: AppType.cardTitle.copyWith(fontSize: 18, color: t.ink),
      contentTextStyle: AppType.body.copyWith(color: t.inkBody),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? t.card : t.ink,
      contentTextStyle: AppType.bodySmall
          .copyWith(color: dark ? t.ink : t.canvas),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: Radii.sm),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: t.navBar,
      indicatorColor: t.brand.withValues(alpha: 0.15),
      labelTextStyle:
          WidgetStatePropertyAll(AppType.navLabel.copyWith(color: t.inkMuted)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.brandInk,
      linearTrackColor: t.track,
      circularTrackColor: Colors.transparent,
    ),
  );
}

final ThemeData appLightTheme = _build(Brightness.light);
final ThemeData appDarkTheme = _build(Brightness.dark);
