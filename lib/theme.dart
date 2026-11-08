import 'package:flutter/material.dart';

/// waydlp palette — identical to the desktop app and website.
abstract final class Palette {
  static const bg = Color(0xFF000000);
  static const bg2 = Color(0xFF080808);
  static const bg3 = Color(0xFF101010);
  static const surface = Color(0xFF121212);
  static const surface2 = Color(0xFF1A1A1A);
  static const accent = Color(0xFF9D4EDD);
  static const accent2 = Color(0xFF7B2CBF);
  static const accentHover = Color(0xFFB56BFF);
  static const accentDark = Color(0xFF5A189A);
  static const text = Color(0xFFFFFFFF);
  static const text2 = Color(0xFFA1A1AA);
  static const muted = Color(0xFF71717A);
  static const border = Color(0xFF242424);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFEAB308);
  static const error = Color(0xFFEF4444);
}

ThemeData buildTheme({Color accent = Palette.accent, bool reduceMotion = false}) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    secondary: Palette.accentHover,
    surface: Palette.bg,
    onSurface: Palette.text,
    surfaceContainerLowest: Palette.bg,
    surfaceContainerLow: Palette.bg2,
    surfaceContainer: Palette.surface,
    surfaceContainerHigh: Palette.surface2,
    surfaceContainerHighest: Palette.surface2,
    outline: Palette.border,
    outlineVariant: Palette.border,
    error: Palette.error,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded.copyWith(side: const BorderSide(color: Palette.border)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.bg2,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette.accentDark,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, color: Palette.text2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.bg3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent),
      ),
      hintStyle: const TextStyle(color: Palette.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: rounded,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: const BorderSide(color: Palette.border),
        shape: rounded,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: Palette.surface2,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(6),
    ),
    dividerTheme: const DividerThemeData(color: Palette.border, space: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.surface2,
      contentTextStyle: TextStyle(color: Palette.text),
      behavior: SnackBarBehavior.floating,
    ),
    pageTransitionsTheme: reduceMotion
        ? const PageTransitionsTheme(builders: {TargetPlatform.android: _NoTransition()})
        : const PageTransitionsTheme(),
  );
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
