import 'package:flutter/material.dart';

class AppColors {
  static const seed = Color(0xFF0E7C66);
  static const income = Color(0xFF16A34A);
  static const expense = Color(0xFFDC2626);
  static const accent = Color(0xFF8B5CF6);
  static const warning = Color(0xFFF59E0B);

  static const gradStart = Color(0xFF0E7C66);
  static const gradEnd = Color(0xFF14B8A6);

  static const incomeGradStart = Color(0xFF15803D);
  static const incomeGradEnd = Color(0xFF22C55E);

  static const expenseGradStart = Color(0xFFB91C1C);
  static const expenseGradEnd = Color(0xFFEF4444);

  static const netGradStart = Color(0xFF6D28D9);
  static const netGradEnd = Color(0xFFA78BFA);

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
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: b,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light
        ? const Color(0xFFF6F8F7)
        : const Color(0xFF0F1413),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: b == Brightness.light
          ? const Color(0xFFF6F8F7)
          : const Color(0xFF0F1413),
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: b == Brightness.light ? Colors.white : const Color(0xFF1A2120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b == Brightness.light
          ? Colors.white
          : const Color(0xFF1A2120),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: b == Brightness.light ? Colors.white : const Color(0xFF1A2120),
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
  );
}

final ThemeData appLightTheme = _build(Brightness.light);
final ThemeData appDarkTheme = _build(Brightness.dark);
