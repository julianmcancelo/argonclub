import 'package:flutter/material.dart';

/// Identidad visual argentina de ArgonAPP.
abstract final class ArgonTheme {
  static const sky = Color(0xFF74ACDF);
  static const skyBright = Color(0xFF9ED2F1);
  static const navy = Color(0xFF061A33);
  static const navySoft = Color(0xFF0B2748);
  static const white = Color(0xFFF7FBFF);
  static const gold = Color(0xFFF6B40E);
  static const success = Color(0xFF55D68B);

  static const argentinaGradient = LinearGradient(
    colors: [skyBright, white, sky],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData darkTheme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: sky,
          brightness: Brightness.dark,
          surface: navy,
        ).copyWith(
          primary: sky,
          secondary: gold,
          surface: navy,
          onSurface: white,
          error: const Color(0xFFFF6B6B),
        );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      primaryColor: sky,
      scaffoldBackgroundColor: const Color(0xFF020A14),
      splashColor: sky.withValues(alpha: 0.18),
      highlightColor: sky.withValues(alpha: 0.08),
      focusColor: sky.withValues(alpha: 0.28),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: sky),
      scrollbarTheme: ScrollbarThemeData(thickness: WidgetStateProperty.all(0)),
    );
  }
}
